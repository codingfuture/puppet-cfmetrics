#
# Copyright 2018 (c) Andrey Galkin
#


class cfmetrics::collector (
    Enum['netdata']
        $type = 'netdata',
) {
    include "cfmetrics::${type}"

    Cfmetrics::Collector::Nginx <| |>
}
