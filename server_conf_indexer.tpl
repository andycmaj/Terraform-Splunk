[replication_port://${replication_port}]

[clustering]
mode = slave
master_uri = https://cluster-master.service.consul:${mgmtHostPort}
pass4SymmKey = ${pass4SymmKey}
