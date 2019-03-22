#
# Copyright 2018-2019 (c) Andrey Galkin
#

define cfmetrics::collector::haproxy (
    String[1] $group,
    String[1] $socket,
) {
    if $cfmetrics::collector::type == 'netdata' {
        $user = $cfmetrics::netdata::user
        $service_name = $cfmetrics::netdata::service_name

        cfsystem::add_group($user, $group)
        -> Cfmetrics_collector[$service_name]
    }
}
