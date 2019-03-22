#
# Copyright 2018-2019 (c) Andrey Galkin
#

class cfmetrics::statshost(
    String[1] $host = 'stats.localdomain',
    String[1] $ip = '127.1.1.1',
) {
    ensure_resource('host', $host, {
        ip => '127.1.0.1',
    })
}
