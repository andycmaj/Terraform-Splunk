## AWS Specific part
variable "ami" {}

variable "instance_user" {}

variable "key_name" {}

variable "consul_server" {}

variable "key_path" {
  description = "Path to the private key specified by key_name."
  default     = "~/.ssh/dev_key.pem"
}

variable "region" {}

variable "pretty_name" {
  default = "splunk"
}

#admin cidr for ssh and web access
variable "admin_cidr_block" {}

# Pick an address far in the subnet to make sure other hosts don't take it first on dhcp
variable "deploymentserver_ip" {}

## Instance/elb/asg specs
variable "instance_type_indexer" {}

variable "instance_type_deploymentserver" {}

variable "instance_type_master" {}

variable "instance_type_searchhead" {}

#elb public/private setting must be set to true or false
variable "elb_internal" {}

# SearchHead Autoscaling
variable "asg_searchhead_desired" {
  default = 2
}

variable "asg_searchhead_min" {
  default = 2
}

variable "asg_searchhead_max" {
  default = 2
}

variable "count_indexer" {
  default = 2
}

## Splunk Settings
variable "httpport" {
  default = 8000
}

variable "indexer_volume_size" {
  default = "50"
}

variable "mgmtHostPort" {
  default = 8089
}

variable "pass4SymmKey" {}

variable "replication_factor" {
  default = 2
}

variable "replication_port" {
  default = 9887
}

variable "search_factor" {
  default = 2
}
