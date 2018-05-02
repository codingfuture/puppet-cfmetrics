#
# Copyright 2018 (c) Andrey Galkin
#


begin
    require File.expand_path( '../../../../puppet_x/cf_system', __FILE__ )
rescue LoadError
    require File.expand_path( '../../../../../../cfsystem/lib/puppet_x/cf_system', __FILE__ )
end

Puppet::Type.type(:cfmetrics_collector).provide(
    :cfprov,
    :parent => PuppetX::CfSystem::ProviderBase
) do
    desc "Provider for cfmetrics_collector"
    
    commands :sudo => PuppetX::CfSystem::SUDO
    commands :systemctl => PuppetX::CfSystem::SYSTEMD_CTL
        
    def self.get_config_index
        'cf90netdata'
    end

    def self.get_generator_version
        cf_system().makeVersion(__FILE__)
    end
    
    def self.check_exists(params)
        debug("check_exists: #{params}")
        begin
            systemctl(['status', "#{params[:service_name]}.service"])
        rescue => e
            warning(e)
            #warning(e.backtrace)
            false
        end
    end

    def self.on_config_change(newconf)
        debug('on_config_change')

        new_services = []

        newconf.each do |name, conf|
            new_services << conf[:service_name]

            begin
                self.send("create_netdata", conf)
            rescue => e
                warning(e)
                #warning(e.backtrace)
                err("Transition error in setup")
            end
        end
    end

    def self.create_netdata(conf)
        debug('on_config_change')
        
        service_name = conf[:service_name]
        settings_tune = conf[:settings_tune]
        cfmetrics_settings = settings_tune.fetch('cfmetrics', {})
        
        avail_mem = cf_system.getMemory(service_name)
        
        user = 'netdata'
        root_dir = '/opt/netdata'
        conf_dir = "#{root_dir}/etc/netdata/"
        cache_dir = "/var/cache/netdata"
        
        need_restart = false

        port = cfmetrics_settings['port']
        listen = cfmetrics_settings['listen']
        target = cfmetrics_settings['target']
        tsdb = cfmetrics_settings['tsdb']
        registry = cfmetrics_settings['registry']
        registry_url = cfmetrics_settings['registry_url']
        alerta = cfmetrics_settings['alerta']
        
        #---
        conf_file = "#{conf_dir}/netdata.conf"
        conf_settings = {
            'global' => {
                'hostname' => Facter['fqdn'].value(),
                'config directory' => conf_dir,
                'cache directory' => cache_dir,
                'error log' => 'syslog',
                'access log' => 'syslog',
                'run as user' => user,
                'update every' => '1',
                'history' => '600',
                'default port' => port,
            },
            'web' => {
                'bind to' => "#{listen}:#{port}",
            },
            'registry' => {},
        }

        if target
            conf_settings['global']['memory mode'] = 'none'
            conf_settings['web']['mode'] = 'none'
        end

        if tsdb
            conf_settings['backend'] = {
                'enabled' => 'yes',
                'data source' => 'average',
                'update every' => '60',
                'type' => 'opentsdb',
                'destination' => tsdb,
            }
        end

        if registry
            conf_settings['registry']['enabled'] = 'yes'
        end

        if registry_url
            conf_settings['registry']['registry to announce'] = registry_url
        end

        # tunes
        settings_tune.each do |k, v|
            next if k == 'cfmetrics'
            conf_settings[k] = {} if not conf_settings.has_key? k
            conf_settings[k].merge! v
        end

        # write
        conf_changed = cf_system.atomicWriteIni(conf_file, conf_settings, { :user => user })
        need_restart ||= conf_changed

        # Database health checks
        #==================================================
        db_health_conf = {}
        db_instance_index = Puppet::Type.type(:cfdb_instance).provider(:cfdb).get_config_index
        db_role_index = Puppet::Type.type(:cfdb_role).provider(:cfdb).get_config_index
        db_instances = cf_system().config.get_new(db_instance_index) || {}
        db_roles = cf_system().config.get_new(db_role_index) || {}

        healthcheck = 'cfdbhealth'
        db_roles.each { |k, rinfo|
            next unless rinfo[:user] == healthcheck && rinfo[:database] == healthcheck

            cluster = rinfo[:cluster]
            password = rinfo[:password]
            cinfo = db_instances[cluster]
            db_type = cinfo[:type]

            case db_type
            when 'mysql'
                check_conf = {
                    'user'   => healthcheck,
                    'pass'   => password,
                    'socket' => "/run/#{cinfo[:service_name]}/service.sock",
                }
            when 'postgresql'
                db_type = 'postgres'
                settings_tune_cfdb = cinfo[:settings_tune]['cfdb']
                check_conf = {
                    'database' => healthcheck,
                    'user'     => healthcheck,
                    'password' => password,
                    'host'     => settings_tune_cfdb['listen'] || '127.0.0.1',
                    'port'     => settings_tune_cfdb['port'],
                }
            when 'elasticsearch'
                settings_tune_cfdb = cinfo[:settings_tune]['cfdb']
                check_conf = {
                    'host'     => settings_tune_cfdb['listen'] || '127.0.0.1',
                    'port'     => settings_tune_cfdb['port'],
                }
            else
                next
            end

            check_conf['autodetection_retry'] = 1
            check_conf['retries'] = 2147483647

            db_health_conf[db_type] ||= {}
            db_health_conf[db_type][cluster] = check_conf
        }

        db_health_conf.each { |db_type, db_conf|
            cf_system.atomicWrite("#{conf_dir}/python.d/#{db_type}.conf",
                                  db_conf.to_yaml, { :user => user })
        }

        # HAProxy configs
        #==================================================
        haproxy_conf = {}
        db_haproxy_index = Puppet::Type.type(:cfdb_haproxy).provider(:cfdb).get_config_index
        db_haproxy = cf_system().config.get_new(db_haproxy_index) || {}

        db_haproxy.each { |k ,v|
            haproxy_service_name = v[:service_name]
            haproxy_conf[haproxy_service_name] = {
                'socket' => "/run/#{haproxy_service_name}/stats.sock",
                'autodetection_retry' => 1,
                'retries' => 2147483647,
            }
        }

        cf_system.atomicWrite("#{conf_dir}/python.d/haproxy.conf",
                              haproxy_conf.to_yaml, { :user => user })

        # puppet configs
        #==================================================
        puppet_conf = {}
        puppetserver_index = Puppet::Type.type(:cf_puppetserver).provider(:cfprov).get_config_index
        puppetdb_index = Puppet::Type.type(:cf_puppetdb).provider(:cfprov).get_config_index
        fqdn = Facter['fqdn'].value()

        if cf_system().config.get_new(puppetserver_index).size > 0
            puppet_conf['puppetdb'] = {
                'url' => "https://#{fqdn}:8140",
                'tls_ca_file'   => "#{root_dir}/pki/puppet/ca.crt",
                'tls_key_file'  => "#{root_dir}/pki/puppet/local.key",
                'tls_cert_file' => "#{root_dir}/pki/puppet/local.crt",
                'autodetection_retry' => 1,
                'retries' => 2147483647,
            }
        end

        if cf_system().config.get_new(puppetdb_index).size > 0
            puppet_conf['puppetserver'] = {
                'url'           => "https://#{fqdn}:8140",
                'autodetection_retry' => 1,
                'retries' => 2147483647,
            }
        end

        cf_system.atomicWrite("#{conf_dir}/python.d/puppet.conf",
                              puppet_conf.to_yaml, { :user => user })


        # Service File
        #==================================================
        start_timeout = 60

        content_ini = {
            'Unit' => {
                'Description' => "CF netdata",
            },
            'Service' => {
                '# Package Version' => File.read("#{root_dir}/usr/share/netdata/web/version.txt"),
                '# Config Version' => PuppetX::CfSystem.makeVersion(conf_dir),
                'ExecStart' => "#{root_dir}/usr/sbin/netdata -P /run/#{service_name}/netdata.pid -D",
                'WorkingDirectory' => root_dir,
                'TimeoutStopSec' => "60",
                'EnvironmentFile' => "-#{root_dir}/.env",
            },
        }
        
        service_changed = self.cf_system().createService({
            :service_name => service_name,
            :user => user,
            :content_ini => content_ini,
            :cpu_weight => conf[:cpu_weight],
            :io_weight => conf[:io_weight],
            :mem_limit => avail_mem,
            :mem_lock => true,
            :cow_reserve => 32,
        })
        
        need_restart ||= service_changed

        #==================================================
        systemctl('enable', "#{service_name}.service")
        
        if need_restart
            warning(">> reloading #{service_name}")
            systemctl('restart', "#{service_name}.service")
        else
            systemctl('start', "#{service_name}.service")
        end

        if alerta
            begin
                sudo(['-u', user, '/opt/netdata/netdata-plugins/plugins.d/alarm-notify.sh', 'test'])
            rescue
                warning('Unable to send alerts to configured alerta.io instance')
            end
        end
    end
end
