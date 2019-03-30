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

        $role_info_raw = cfsystem::query([
            'from', 'resources', ['extract', [ 'certname', 'parameters' ],
                ['and',
                    ['=', 'type', 'Cfdb_role'],
                    ['=', ['parameter', 'cluster'], $cluster],
                    ['=', ['parameter', 'user'], $role],
            ],
        ]])

        $role_info = size($role_info_raw) ? {
            0       => {
                'password' => cfsystem::gen_pass("cfdb/${cluster}@${role}", 16),
            },
            default => $role_info_raw[0]['parameters']
        }

        cfdb_access{ "cfmetrics:${title}":
            ensure          => present,
            cluster         => $cluster,
            role            => $role,
            local_user      => $user,
            max_connections => 2,
            client_host     => 'localhost',
            config_info     => {
                password => $role_info['password']
            },
            require         => Anchor['cfnetwork:firewall'],
        }

        cfnetwork::client_port { "local:cfdb_${cluster}:${user}":
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
