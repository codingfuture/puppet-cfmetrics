#
# Copyright 2018 (c) Andrey Galkin
#

define cfmetrics::collector::nginx() {
    include cfmetrics::statshost

    $statshost = $cfmetrics::statshost::host
    $sites_dir = $cfweb::nginx::sites_dir

    Host[$statshost]
    -> file {"${sites_dir}/stats.conf":
        mode    => '0640',
        content => epp('cfmetrics/nginx/stats.conf.epp', {
            host      => $statshost,
            sites_dir => $sites_dir,
        }),
    }
    -> file {"${sites_dir}/stats.server.nginx":
        mode    => '0640',
        content => epp('cfmetrics/nginx/nginx.conf.epp', {}),
    }
    ~> Exec['cfweb_reload']

    if $cfmetrics::collector::type == 'netdata' {
        $user = $cfmetrics::netdata::user

        cfnetwork::client_port { "any:http:${user}":
            user => $user,
        }

        Anchor['netdata-installed']
        -> file { "${cfmetrics::netdata::root_dir}/etc/netdata/python.d/nginx.conf":
            mode    => '0640',
            owner   => $user,
            content => to_yaml({
                "${title}" => {
                    url                 => "http://${statshost}/nginx",
                    autodetection_retry => 1,
                    retries             => 2147483647,
                },
            }),
        }
        ~> Service[$cfmetrics::netdata::service_name]

        Exec['cfweb_reload']
        -> Service[$cfmetrics::netdata::service_name]
    }
}
