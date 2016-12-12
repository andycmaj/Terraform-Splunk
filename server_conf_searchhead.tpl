[general]
allowRemoteLogin = always

[clustering]
mode = searchhead
master_uri = https://cluster-master:${mgmtHostPort}
pass4SymmKey = ${pass4SymmKey}

[replication_port://${replication_port}]

[shclustering]
id = 776D2949-B2DA-405E-96B3-B6688C87AB7D
conf_deploy_fetch_url = https://cluster-master:${mgmtHostPort}
disabled = false
election_timeout_ms = 10000
mgmt_uri = https://LOCAL_IP:8089
pass4SymmKey = ${pass4SymmKey}
replication_factor = 2
shcluster_label = shcluster
