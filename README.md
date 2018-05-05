# cfmetrics

Centralized metrics collection and monitoring solution.

## Description

* Neutral collector interface:
    * netdata (default)
        - Real-time monitoring
        - Easy integration with Graphite, OpenTSDB and Prometheus
        - Very fast and resource efficient
        - Easily extendable
        - StatsD emulation
        - Integrated with cfsystem memory distribution.
* Specialized alert managing software support
    - fine control of notification methods
    - advanced filtering & history
    - access control
* Plug & Play integration with other cf* modules


### Terminology & Concept

* **Collector** - abstract definition of collecting feature.
* **cfsystem::metric** - abstract declaration of "collectable" resource.
* **Target** - host to send metrics to collector-defined way.
* **Alert** - preconfigured notification for infrastructure health state.
* **AlertManager** - special high-available solution for Alert notifications like Alerta.io

Collector gather all system info it can. All `cf*` modules declare support for metrics
of various services. If `cfmetrics` module is loaded then the declarations are used
to automatically discover resources to monitor.

#### Netdata collector

Netdata allows building efficient data gathering topology. By default, all instances
act in standalone mode with own history. If collector target is configured, then netdata
does not maintain history - only push buffer.

It's possible to run own netdata registry.

Both binary and source installations are possible. Automatic update is tried on Puppet
catalog run, but not more often than once in 1 hour.

Just for reference, a special LogStash instance accepting TSDB input format is supported
to store metrics in Elasticsearch the efficient way. It suits small scale to unify
logging and metrics centralization. For larger cases, Prometheus is suggested.

Even with configured AlertManager, critical Alerts are duplicated via email.

## Technical Support

* [Website](https://codingfuture.net/docs/)
* [Example configuration](https://github.com/codingfuture/puppet-test)
* Free & Commercial support: [support@codingfuture.net](mailto:support@codingfuture.net)

## Setup

Up to date installation instructions are available in Puppet Forge: https://forge.puppet.com/codingfuture/cfmetrics

Please use [librarian-puppet](https://rubygems.org/gems/librarian-puppet/) or
[cfpuppetserver module](https://codingfuture.net/docs/cfpuppetserver) to deal with dependencies.

There is a known r10k issue [RK-3](https://tickets.puppetlabs.com/browse/RK-3) which prevents
automatic dependencies of dependencies installation.

## API

### `cfmetrics` class

Main class of the module.

* `$collect = true` - enabled collector
* `$iface = 'local'` - default iface to bind services to

### `cfmetrics::collector` class

Generic collector functionality.

* `$type = 'netdata'` - collector implementation to use

### `cfmetrics::netdata` class

* Standard cfsystem resource limits:
    * `$memory_weight = 1`
    * `$memory_min = undef`
    * `$memory_max = undef`
    * `$cpu_weight = 10`
    * `$io_weight = 10`
* `$iface = $cfmetrics::iface` - interface to listed for requests
* `$port = undef` - networks port to bind
* `$target = undef` - configure upstream target (hostname)
* `$server = false` - act as server (upstream target)
* `$registry = false` - enable local netdata registry
* `$registry_url = undef` - setup non-default registry URL
* `$settings_tune = {}` - fine tune of netdata configuration
    - all keys directly go to YAML, except special `cfmetrics`:
        - `base_mem = 48` - base memory for netdata (requires noticeable amount for Python)
        - `history_mem = 10` - how much memory to reserve per single host history
* `$binary_install = true` - use binary install instead of git source based
* `$mirror = 'https://my-netdata.io'` - what mirror to use for install script (system proxy aware)
* `$extra_clients = []` - define static list of possible netdata clients
* `$logstash = undef` - LogStash TSDB-mode configuration support
* `$alerta = undef` - define Alerta.io API endpoint support:
    - `url` - endpoint URL
    - `key` - secret API key
    - `env` - Alerta.io environment (scope)
* `$alarm_conf = {}` - fine tune of alarm config

