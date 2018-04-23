#
# Copyright 2018 (c) Andrey Galkin
#


class cfmetrics::netdata (
    Integer[1]
        $memory_weight = 1,
    Optional[Integer[1]]
        $memory_min = undef,
    Optional[Integer[1]]
        $memory_max = undef,
    Cfsystem::CpuWeight
        $cpu_weight = 10,
    Cfsystem::IoWeight
        $io_weight = 10,

    Cfnetwork::Bindface
        $iface = $cfmetrics::iface,
    Optional[Integer[1]]
        $port = undef,
    Optional[String[1]]
        $target = undef,
    Boolean
        $server = false,

    Hash
        $settings_tune = {},
    Boolean
        $binary_install = true,
    String[1]
        $mirror = 'https://my-netdata.io',

    Array[String[1]]
        $extra_clients = [],

    Optional[ Hash[String[1],Any] ]
        $logstash = undef,
) {
    $user = 'netdata'
    $group = $user
    $service_name = 'netdata'
    $root_dir = '/opt/netdata'

    # Based on: https://github.com/firehol/netdata/wiki/Installation#1-prepare-your-system

    ensure_packages([
        'bash', 'curl', 'iproute',
        'python', 'python-yaml', 'python-beanstalkc',
        'python-dnspython', 'python-ipaddress',
        # to be part of cfdb setup metric setup
        # 'python-mysqldb', 'python-psycopg2', 'python-pymongo',
        'lm-sensors', 'libmnl0', 'netcat',
        # misc
        'libnetfilter-acct1',
    ])

    if $binary_install {
        $exec_name = 'Install netdata from binary'
        $install_script = 'kickstart-static64.sh'
        $extra_opts = ''
    } else {
        $exec_name = 'Install netdata from source'
        $install_script = 'kickstart.sh'
        $extra_opts = '--install /opt'
    }

    if empty($cfsystem::http_proxy) {
        $curl_env = []
    } else {
        $curl_env = [
            "http_proxy=${cfsystem::http_proxy}",
            "HTTPS_PROXY=${cfsystem::http_proxy}",
        ]
    }

    $latest_binary_stamp = '/etc/cfsystem/netdata-latest.gz.run'
    $installled_binary_stamp = "${root_dir}/etc/netdata/uptodate.stamp"

    # Get new version not more often than once per day.
    # The stamp can be always removed manually to force update check.
    exec { 'Getting latest netdata version':
        command => [
            "/usr/bin/wget -O${latest_binary_stamp}.tmp",
            "'https://raw.githubusercontent.com/firehol/binary-packages/master/netdata-latest.gz.run'",
            "&& /bin/mv -f ${latest_binary_stamp}.tmp ${latest_binary_stamp}",
        ].join(' '),
        unless  => "/usr/bin/find ${latest_binary_stamp} -mtime -1 | /bin/grep -q '^'",
    }
    -> file { $latest_binary_stamp:
        ensure  => file,
        content => '',
        replace => false,
    }
    -> exec { $exec_name:
        command     => ([
            '/usr/bin/curl -Ssf --connect-timeout 5',
            "${mirror}/${install_script} |",
            '/bin/bash',
            '--',
            '/dev/stdin',
            '--dont-wait --dont-start-it',
            $extra_opts,
            "&& /bin/cp -f ${latest_binary_stamp} ${installled_binary_stamp}",
        ]).join(' '),
        unless      => "/usr/bin/diff -q ${latest_binary_stamp} ${installled_binary_stamp}",
        environment => $curl_env,
    }
    -> anchor { 'netdata-installed': }

    #---
    if $iface == 'any' {
        $listen = '*'
    } else {
        $listen = cfnetwork::bind_address($iface)
    }

    $fact_port = cfsystem::gen_port($service_name, $port)

    # Allowing clients
    #---
    if $server {
        if $iface == 'local' {
            fail('Cannot mix server=true and iface=local')
        }

        $clients = cfsystem::query([
            'from', 'resources',
                ['extract', [ 'certname', 'parameters' ],
                    ['and',
                        ['=', 'title', 'Cfmetrics::Netdata'],
                        ['=', 'type', 'Class'],
                        [ '=', ['parameter', 'target'], $::facts['fqdn'] ],
                    ],
                ],
        ])

        $client_hosts = $clients.reduce( [] ) |$memo, $v| {
            $memo + $v['certname']
        }

        ensure_resource('cfnetwork::describe_service', $user, {
            server => "tcp/${fact_port}",
        })

        cfnetwork::service_port { "local:${user}": }
        cfnetwork::client_port { "local:${user}":
            user => [ $user, 'root' ],
        }

        $access_ipset = 'cfmetrics_access'
        cfnetwork::ipset { $access_ipset:
            addr => ['ipset:localnet'] + $extra_clients,
        }
        cfnetwork::service_port { "${iface}:${user}":
            src => ["ipset:${access_ipset}"],
        }
    }

    # Target
    #---
    if $target and $target != $::facts['fqdn'] {
        $target_info = cfsystem::query([
            'from', 'resources',
                ['extract', [ 'parameters' ],
                    ['and',
                        ['=', 'type', 'Cfmetrics_collector'],
                        ['=', 'certname', $target],
                        ['=', 'title', $service_name],
                    ],
                ],
        ])

        if $target_info.size == 1 {
            $target_params = $target_info[0]['parameters']['settings_tune']['cfmetrics']

            $target_listen = $target_params['listen'] ? {
                '*' => $target,
                default => $target_params['listen']
            }
            $target_port = $target_params['port']
            $target_address = "${target_listen}:${target_port}"

            $target_fw_service = "${user}_target"

            ensure_resource('cfnetwork::describe_service', $target_fw_service, {
                server => "tcp/${target_port}",
            })

            cfnetwork::client_port { "any:${target_fw_service}":
                user => $user,
                dst  => $target_listen,
            }
        } else {
            $target_address = undef

            cf_notify { 'cfmetrics::netdata::target':
                message  => "Failed to find cfmetrics '${target}' target",
                loglevel => warning,
            }
        }
    } else {
        $target_address = undef
    }

    # StatsD emulation
    #---
    $statsd_port = 8125
    cfsystem::gen_port('statsd', $statsd_port)
    ensure_resource('cfnetwork::describe_service', 'statsd', {
        server => [
            "tcp/${statsd_port}",
            "udp/${statsd_port}",
        ]
    })

    cfnetwork::service_port { 'local:statsd': }
    cfnetwork::client_port { 'local:statsd': }

    # Auto calculate memory
    #---
    $cfmetrics_tune = pick($settings_tune['cfmetrics'], {})
    $base_mem = pick($cfmetrics_tune['base_mem'], 32)
    $history_mem = pick($cfmetrics_tune['history_mem'], 10)

    if $server {
        $auto_memory_min = $base_mem + $history_mem + ($history_mem * size($clients))
    } elsif $target_address {
        $auto_memory_min = $base_mem
    } else {
        $auto_memory_min = $base_mem + $history_mem
    }


    # Logstash-based backend for small/medium scale
    #---
    if $logstash {
        $logstash_port = cfsystem::gen_port('cflogstash-metrics', $logstash['port'])
        $tsdb = "127.0.0.1:${logstash_port}"

        file { '/etc/cfsystem/cfmetrics_elasticsearch.json':
            mode    => '0644',
            content => file('cfmetrics/metrics-template-es6x.json'),
        }
        -> Cflogsink::Endpoint['netdata']

        create_resources('cflogsink::endpoint', {
            'netdata' => {
                type          => 'logstash',
                config        => 'cfmetrics/logstash_netdata.conf.epp',
                iface         => 'local',
                port          => $logstash_port,
                settings_tune => merge(
                    {
                        'pipeline.batch.size' => 1024,
                    },
                    pick($logstash['settings_tune'], {})
                ),
            }
        }, $logstash)

        cfnetwork::client_port { 'local:logstash_netdata:tsdb':
            user => $user,
        }
    } else {
        $tsdb = undef
    }

    #---
    $act_settings = $settings_tune + {
        'global' => {
            'update every' => 1,
            'history' => 600,
        },
        'cfmetrics' => merge(
            $cfmetrics_tune,
            {
                port   => $fact_port,
                listen => $listen,
                target => $target_address,
                tsdb   => $tsdb,
            }
        ),
    }

    group { $group:
        ensure => present,
    }
    -> user { $user:
        ensure  => present,
        gid     => $group,
        home    => $root_dir,
        require => Group[$group],
    }
    -> Anchor['netdata-installed']
    -> file { "${root_dir}/etc/netdata/stream.conf":
        owner   => $user,
        group   => $user,
        mode    => '0600',
        content => epp('cfmetrics/netdata_stream.conf.epp'),
    }
    -> file { '/var/cache/netdata':
        ensure => directory,
        owner  => $user,
        group  => $user,
        mode   => '0700',
    }
    -> cfsystem_memory_weight { $service_name:
        ensure => present,
        weight => $memory_weight,
        min_mb => pick($memory_min, $auto_memory_min),
        max_mb => pick($memory_max, $auto_memory_min*2),
    }
    -> cfmetrics_collector { $service_name:
        ensure        => present,
        memory_weight => $memory_weight,
        cpu_weight    => $cpu_weight,
        io_weight     => $io_weight,
        settings_tune => $act_settings,
        service_name  => $service_name,
    }
}
