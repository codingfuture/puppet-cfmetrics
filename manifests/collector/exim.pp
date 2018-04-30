#
# Copyright 2018 (c) Andrey Galkin
#

define cfmetrics::collector::exim {
    if $cfmetrics::collector::type == 'netdata' {
        $user = $cfmetrics::netdata::user
        $service_name = $cfmetrics::netdata::service_name
        $cmd = '/usr/sbin/exim -bpc'

        Anchor['netdata-installed']
        -> cfauth::sudoentry { "${user}:exim":
            user          => $user,
            custom_config => [
                "Cmnd_Alias EXIM_BPC = ${cmd}",
                'Defaults!EXIM_BPC !syslog'
            ],
            command       => 'EXIM_BPC',
        }
        -> file { "${cfmetrics::netdata::root_dir}/etc/netdata/python.d/exim.conf":
            mode    => '0640',
            owner   => $user,
            content => to_yaml({
                local => {
                    command             => "/usr/bin/sudo ${cmd}",
                    update_every        => 5,
                    autodetection_retry => 1,
                    retries             => 2147483647,
                },
            }),
        }
        ~> Service[$service_name]
    }
}
