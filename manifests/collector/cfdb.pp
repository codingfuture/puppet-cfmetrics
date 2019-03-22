#
# Copyright 2018-2019 (c) Andrey Galkin
#

define cfmetrics::collector::cfdb (
    String[1] $type,
    String[1] $cluster,
    String[1] $role,
) {
    if $cfmetrics::collector::type == 'netdata' {
        $user = $cfmetrics::netdata::user
        $service_name = $cfmetrics::netdata::service_name

        cfdb_access{ "cfmetrics:${title}":
            ensure          => present,
            cluster         => $cluster,
            role            => $role,
            local_user      => $user,
            max_connections => 2,
            client_host     => 'localhost',
            config_info     => {},
            require         => Anchor['cfnetwork:firewall'],
        }

        cfnetwork::client_port { "local:cfdb_${cluster}::${user}":
            user => $user,
        }

        cfsystem_memory_weight { "${service_name}/cfdb-${title}":
            ensure => present,
            weight => 0,
            min_mb => 4,
            max_mb => 4,
        }
    }
}
