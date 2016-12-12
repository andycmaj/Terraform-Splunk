[serverClass:sc_master]
stateOnClient = "noop"
whitelist.0 = cluster-master

[serverClass:sc_searchhead]
whitelist.0 = *
blacklist.0 = cluster-master
