[global]
whitelist.0 = *

[serverClass:sc_master]
stateOnClient = "noop"
whitelist.0 = cluster-master.service.consul

[serverClass:sc_searchhead]
whitelist.0 = *
blacklist.0 = cluster-master.service.consul
