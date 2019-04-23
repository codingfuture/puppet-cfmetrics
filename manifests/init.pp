#
# Copyright 2018-2019 (c) Andrey Galkin
#


class cfmetrics (
    Boolean
        $collect = true,
    Cfnetwork::Bindface
        $iface = 'local',
    Boolean
        $prometheus = false,
) {
    if $collect {
        include cfmetrics::collector
    }

    if $prometheus {
        include cfmetrics::prometheus
    }
}
