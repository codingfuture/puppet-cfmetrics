#
# Copyright 2019 (c) Andrey Galkin
#


class cfmetrics::alertmanager(
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
        $alertmanager_tune = {},
    CfWeb::DockerImage $image = {
        image => 'prom/alertmanager',
        image_tag => 'latest',
    },

    String[1] $server_name = "alertmanager.${::facts['fqdn']}",
    Hash[String[1], Any] $site_params = {},
    Hash $rules = {},
) {
    include cfmetrics::collector
    include cfweb::appcommon::docker
    include cfweb::nginx

    if !$cfsystem::email::listen_ifaces or (
        !('docker' in $cfsystem::email::listen_ifaces) and
        !('any' in $cfsystem::email::listen_ifaces)
    ) {
        fail('Host email system must listen on "docker" interface')
    }

    $user = 'app_prometheus'
    $site_dir = "${cfweb::nginx::web_dir}/${user}"

    $alertmanager_tune_all = deep_merge(
        {
            global => {
                smtp_smarthost => '172.18.0.1:25',
                smtp_from => "alert@${::trusted['domain']}",
            },
            route => {
                receiver => admin,
            },
            receivers => [
                name => admin,
                email_configs => {
                    to => pick($cfsystem::admin_email, "admin@${::trusted['domain']}"),
                }
            ],
        },
        $alertmanager_tune,
    )

    $config_file = "${site_dir}/persistent/alertmanager.yml"

    file { "${site_dir}/persistent/data":
        ensure => directory,
        mode   => '0777',
        owner  => $user,
    }
    file { $config_file:
        mode    => '0644',
        owner   => $user,
        content => $alertmanager_tune_all.to_yaml(),
    }

    # ---
    ensure_resource('cfweb::site', 'alertmanager', {
        ifaces             => [ $iface ],
        tls_ports          => [],
    } + $site_params + {
        server_name        => $server_name,
        apps               => {
            docker => {
                memory_weight => $memory_weight,
                memory_min    => $memory_min,
                memory_max    => $memory_max,
                upstream      => { port => $port },
            },
        },
        deploy             => {
            target_port   => 9090,
            image         => $image,
            binds         => {
                'alertmanager.yml' => '/etc/alertmanager/alertmanager.yml',
                'data' => '/alertmanager',
            },
            config_files  => [$config_file],
            network       => 'prometheus',
        },
    })

}
