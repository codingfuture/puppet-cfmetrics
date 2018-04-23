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

        # tunes
        settings_tune.each do |k, v|
            next if k == 'cfmetrics'
            conf_settings[k] = {} if not conf_settings.has_key? k
            conf_settings[k].merge! v
        end

        # write
        conf_changed = cf_system.atomicWriteIni(conf_file, conf_settings, { :user => user })
        need_restart ||= conf_changed

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
    end
end
