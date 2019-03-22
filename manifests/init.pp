#
# Copyright 2018-2019 (c) Andrey Galkin
#


class cfmetrics (
    Boolean
        $collect = true,
    Cfnetwork::Bindface
        $iface = 'local',
) {
    if $collect {
        include cfmetrics::collector
    }
}
