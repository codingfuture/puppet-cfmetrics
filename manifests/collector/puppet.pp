#
# Copyright 2018 (c) Andrey Galkin
#


define cfmetrics::collector::puppet(
    $fw_service,
) {
    if $cfmetrics::collector::type == 'netdata' {
        $user = $cfmetrics::netdata::user

        ensure_resource( 'cfnetwork::client_port', "local:${fw_service}:${user}", {
            user => $user,
        } )

        if $title == 'puppetdb' {
            cfsystem::puppetpki { $user: }
        }
    }
}
