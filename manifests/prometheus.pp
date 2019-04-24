#
# Copyright 2019 (c) Andrey Galkin
#


class cfmetrics::prometheus(
    Integer[1]
        $memory_weight = 1,
    Optional[Integer[1]]
        $memory_min = 256,
    Optional[Integer[1]]
        $memory_max = 512,
    Cfsystem::CpuWeight
        $cpu_weight = 10,
    Cfsystem::IoWeight
        $io_weight = 10,

    Cfnetwork::Bindface
        $iface = $cfmetrics::iface,
    Cfnetwork::Port
        $port = 9090,
    Hash
        $prometheus_tune = {},
    CfWeb::DockerImage $image = {
        image => 'prom/prometheus',
        image_tag => 'latest',
    },

    String[1] $server_name = "prometheus.${::facts['fqdn']}",
    Hash[String[1], Any] $site_params = {},
    Hash $rules = {},
    Boolean $alertmanager = true,
) {
    include cfmetrics::collector
    include cfweb::appcommon::docker

    if $cfmetrics::collector::type != 'netdata' {
        fail('Only Netdata collector is supported so far')
    }

    if !$cfmetrics::netdata::server {
        fail('Netdata must be configured in server mode!')
    }
    include cfweb::nginx

    $user = 'app_prometheus'
    $site_dir = "${cfweb::nginx::web_dir}/${user}"

    $netdata_port = $cfmetrics::netdata::fact_port

    if $cfmetrics::netdata::iface == 'any' {
        $netdata_host = cfnetwork::bind_address('docker')
    } elsif $cfmetrics::netdata::iface == 'local' {
        fail('Netdata must not listen on local interface with Prometheus')
    } else {
        $netdata_host = $cfmetrics::netdata::fact_host
    }

    cfnetwork::service_port { "docker:${cfmetrics::netdata::user}:prometheus": }
    cfnetwork::service_port { 'docker:prometheus': }
    cfnetwork::describe_service { 'prometheus':
        server => "tcp/${port}",
    }

    $alertmanagers = $alertmanager ? {
        true => [ { targets => [ '172.18.0.1:9093' ] } ],
        default => [],
    }

    $prometheus_tune_all = deep_merge(
        {
            'global' => {
                'scrape_interval' => '30s',
                'evaluation_interval' => '30s',
            },
            'alerting' => {
                'alertmanagers' => [ {
                    static_configs => $alertmanagers,
                } ],
            },
        },
        $prometheus_tune,
        {
            rule_files     => $rules.map |$k, $v| { "/etc/prometheus/${k}.rules" },
            scrape_configs => [
                {
                    job_name       => prometheus,
                    static_configs => [
                        { targets => ['0.0.0.0:9090'] }
                    ]
                },
                {
                    job_name       => netdata,
                    metrics_path   => '/api/v1/allmetrics',
                    params => {
                        format     => [prometheus_all_hosts],
                        variables  => ['yes'],
                        timestamps => ['no'],
                    },
                    honor_labels => true,
                    static_configs => [
                        { targets => ["${netdata_host}:${netdata_port}"] },
                    ],
                },
            ],
        }
    )

    $alertmanagers.each |$v| {
        $hp = $v['targets'][0].split(':')

        if $hp[0] != 'alertmanager' {
            $fws = "alertmanager${hp[1]}"
            ensure_resource(
                'cfnetwork::describe_service',
                $fws,
                { server => "tcp/${hp[1]}" }
            )
            cfnetwork::router_port { "docker/any:${fws}":
                dst => $hp[0],
            }
        }
    }

    $config_file = "${site_dir}/persistent/prometheus.yml"

    file { "${site_dir}/persistent/data":
        ensure => directory,
        mode   => '0777',
        owner  => $user,
    }
    file { $config_file:
        mode    => '0644',
        owner   => $user,
        content => $prometheus_tune_all.to_yaml(),
    }

    $rules.map |$k, $v| {
        $f = "${site_dir}/persistent/${k}.rules"
        file { $f:
            mode    => '0644',
            owner   => $user,
            content => $v.to_yaml(),
        }
    }

    # ---
    ensure_resource('cfweb::site', 'prometheus', {
        ifaces             => [ $iface ],
        tls_ports          => [],
    } + $site_params + {
        server_name        => $server_name,
        apps               => {
            docker => {
                memory_weight => $memory_weight,
                memory_min    => $memory_min,
                memory_max    => $memory_max,
                upstream      => {
                    host => '172.18.0.1',
                    port => $port,
                },
            },
        },
        deploy             => {
            target_port   => 9090,
            image         => $image,
            binds         => $rules.reduce({}) |$m, $v| {
                $m + {
                    "${site_dir}/persistent/${v[0]}.rules" => "/etc/prometheus/${v[1]}.rules",
                }
            } + {
                'prometheus.yml' => '/etc/prometheus/prometheus.yml',
                'data' => '/prometheus',
            },
            config_files  => [$config_file],
        },
    })

    # ---
    if $alertmanager {
        include cfmetrics::alertmanager
    }
}
