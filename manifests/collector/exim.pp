#
# Copyright 2018-2019 (c) Andrey Galkin
#

define cfmetrics::collector::exim {
    if $cfmetrics::collector::type == 'netdata' {
        $user = $cfmetrics::netdata::user
        $service_name = $cfmetrics::netdata::service_name
        $cmd = '/usr/sbin/exim -bpc'

        Anchor['netdata-installed']
        -> cfauth::sudoentry { "${user}:exim":
            user          => $user,
            # NOTE: tehre is still PAM noise in logs
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
                    update_every        => 60,
                    autodetection_retry => 1,
                    retries             => 2147483647,
                },
            }),
        }
        -> cfsystem_memory_weight { "${service_name}/${title}":
            ensure => present,
            weight => 0,
            min_mb => 4,
            max_mb => 4,
        }
        ~> Service[$service_name]
    }
}
