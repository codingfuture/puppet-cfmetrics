#
# Copyright 2018-2019 (c) Andrey Galkin
#

define cfmetrics::collector::ntpd {
    if $cfmetrics::collector::type == 'netdata' {
        $user = $cfmetrics::netdata::user
        $service_name = $cfmetrics::netdata::service_name

        cfnetwork::client_port { "local:ntp:${user}":
            user => $user,
        }

        file { "${cfmetrics::netdata::root_dir}/etc/netdata/python.d/ntpd.conf":
            mode    => '0640',
            owner   => $user,
            content => to_yaml({
                local => {
                    update_every        => 5,
                    autodetection_retry => 1,
                    retries             => 2147483647,
                },
            }),
        }
        ~> Service[$service_name]
    }
}
