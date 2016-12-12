# Specify the provider and access details
provider "aws" {
  region = "${var.region}"
}

# Configure the Consul provider
provider "consul" {
  address    = "${module.consul.server_address}:8500"
  datacenter = "dc1"
}

# HACK: using stack module to generate and provide a VPC/subnets/AZs
# TODO: find a simpler module to do this. stack generates a ton of resources
module "stack" {
  source      = "github.com/segmentio/stack"
  environment = "ac"
  key_name    = "${var.key_name}"
  name        = "splunk"
}

module "consul" {
  source   = "./consul"
  key_name = "${var.key_name}"
  key_path = "~/.ssh/dev_key.pem"
  servers  = 1
}

###################### ELB PART ######################
resource "aws_elb" "search" {
  name = "splunk-elb"

  tags {
    Name = "splunk_elb"
  }

  internal        = "${var.elb_internal}"
  subnets         = ["${module.stack.external_subnets}"]
  security_groups = ["${aws_security_group.elb.id}"]

  instances = ["${aws_instance.searchhead.*.id}"]

  listener {
    instance_port     = "${var.httpport}"
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3

    #Health check does not like redirects so we test a "final" url
    target   = "HTTP:${var.httpport}/en-US/account/login"
    interval = 5
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400
}

resource "aws_lb_cookie_stickiness_policy" "search" {
  name                     = "splunk-lb-policy"
  load_balancer            = "${aws_elb.search.id}"
  lb_port                  = 80
  cookie_expiration_period = 1800
}

resource "aws_app_cookie_stickiness_policy" "splunk" {
  name          = "${var.pretty_name}-stickiness-policy"
  load_balancer = "${aws_elb.search.id}"
  lb_port       = 80

  #Cookie name is base on the web server port
  cookie_name = "session_id_${var.httpport}"
}

###################### Security Groups Part ######################
resource "aws_security_group" "elb" {
  name        = "sg_splunk_elb"
  description = "Used in the terraform"
  vpc_id      = "${module.stack.vpc_id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "all" {
  name        = "sg_splunk_all"
  description = "Common rules for all"
  vpc_id      = "${module.stack.vpc_id}"

  # Allow SSH admin access
  ingress {
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = ["${var.admin_cidr_block}"]
  }

  # Allow Web admin access
  ingress {
    from_port   = "${var.httpport}"
    to_port     = "${var.httpport}"
    protocol    = "tcp"
    cidr_blocks = ["${var.admin_cidr_block}"]
  }

  # full outbound  access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "interco" {
  # Allow all ports between splunk servers
  type                     = "ingress"
  from_port                = "0"
  to_port                  = "0"
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.all.id}"
  source_security_group_id = "${aws_security_group.all.id}"
}

resource "aws_security_group" "searchhead" {
  name        = "sg_splunk_searchhead"
  description = "Used in the  terraform"
  vpc_id      = "${module.stack.vpc_id}"

  #HTTP  access  from  the  ELB
  ingress {
    from_port       = "${var.httpport}"
    to_port         = "${var.httpport}"
    protocol        = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }
}

###################### Templates part ######################
resource "template_file" "serverclass_conf" {
  template = "${file("${path.module}/serverclass_conf.tpl")}"

  vars {
    master_ip = "${aws_instance.master.private_ip}"
  }
}

resource "template_file" "web_conf" {
  template = "${file("${path.module}/web_conf.tpl")}"

  vars {
    httpport     = "${var.httpport}"
    mgmtHostPort = "${var.mgmtHostPort}"
  }
}

resource "template_file" "deploymentclient_conf" {
  template = "${file("${path.module}/deploymentclient_conf.tpl")}"

  vars {
    mgmtHostPort        = "${var.mgmtHostPort}"
    deploymentserver_ip = "${var.deploymentserver_ip}"
  }
}

resource "template_file" "server_conf_master" {
  template = "${file("${path.module}/server_conf_master.tpl")}"

  vars {
    replication_factor = "${var.replication_factor}"
    search_factor      = "${var.search_factor}"
    pass4SymmKey       = "${var.pass4SymmKey}"
  }
}

resource "template_file" "server_conf_indexer" {
  template = "${file("${path.module}/server_conf_indexer.tpl")}"

  vars {
    mgmtHostPort     = "${var.mgmtHostPort}"
    master_ip        = "${aws_instance.master.private_ip}"
    pass4SymmKey     = "${var.pass4SymmKey}"
    replication_port = "${var.replication_port}"
  }
}

resource "template_file" "server_conf_searchhead" {
  template = "${file("${path.module}/server_conf_searchhead.tpl")}"

  vars {
    mgmtHostPort     = "${var.mgmtHostPort}"
    master_ip        = "${aws_instance.master.private_ip}"
    pass4SymmKey     = "${var.pass4SymmKey}"
    replication_port = "${var.replication_port}"
  }
}

resource "template_file" "user_data_master" {
  template = "${file("${path.module}/user_data.tpl")}"

  vars {
    deploymentclient_conf_content = <<EOF
[deployment-client]
serverRepositoryLocationPolicy = rejectAlways
repositoryLocation = \$SPLUNK_HOME/etc/master-apps
${template_file.deploymentclient_conf.rendered}
EOF

    server_conf_content      = "${template_file.server_conf_master.rendered}"
    serverclass_conf_content = ""
    web_conf_content         = "${template_file.web_conf.rendered}"
    role                     = "master"

    # TODO: use provisioner remote-exec instead of this?
    cmds_content = <<EOF
export SPLUNK_CMD_1=cmd python /opt/splunk/bin/splunk_setup.py --wait-splunk 'https://searchhead-1:8089' '(shc_member|shc_captain)'
export SPLUNK_CMD_2=cmd python /opt/splunk/bin/splunk_setup.py --wait-splunk 'https://searchhead-2:8089' '(shc_member|shc_captain)'
export SPLUNK_CMD_4=add search-server searchhead-1:8089 -remoteUsername admin -remotePassword changed -auth admin:changeme
export SPLUNK_CMD_5=add search-server searchhead-2:8089 -remoteUsername admin -remotePassword changed -auth admin:changeme
export SPLUNK_CMD_7=status
    EOF
  }
}

resource "template_file" "user_data_deploymentserver" {
  template = "${file("${path.module}/user_data.tpl")}"

  vars {
    # Deployment server cannot be it's own client
    deploymentclient_conf_content = ""
    server_conf_content           = ""
    serverclass_conf_content      = "${template_file.serverclass_conf.rendered}"
    web_conf_content              = "${template_file.web_conf.rendered}"
    role                          = "deploymentserver"

    cmds_content = ""
  }
}

resource "template_file" "user_data_indexer" {
  template = "${file("${path.module}/user_data.tpl")}"

  vars {
    # Indexers are deploy clients for the cluster master
    deploymentclient_conf_content = ""
    server_conf_content           = "${template_file.server_conf_indexer.rendered}"
    serverclass_conf_content      = ""
    web_conf_content              = "${template_file.web_conf.rendered}"
    role                          = "indexer"

    cmds_content = ""
  }
}

resource "template_file" "user_data_searchhead" {
  template = "${file("${path.module}/user_data.tpl")}"

  vars {
    deploymentclient_conf_content = "${template_file.deploymentclient_conf.rendered}"
    server_conf_content           = "${template_file.server_conf_searchhead.rendered}"
    serverclass_conf_content      = ""
    web_conf_content              = "${template_file.web_conf.rendered}"
    role                          = "searchhead"

    cmds_content = <<EOF
export SPLUNK_CMD_1=cmd python /opt/splunk/bin/splunk_setup.py --shc-autobootstrap ${var.asg_searchhead_desired} https://$${INSTANCE_IP}:8089 admin changed 'https://cluster-master:8089/servicesNS/nobody/system/storage/collections/data/service_discovery' service_discovery_user service_discovery_password
export SPLUNK_CMD_2=status
    EOF
  }
}

resource "template_file" "consul_agent_install" {
  template = "${path.module}/consul/scripts/install.tpl"

  vars {
    consul_params = "-advertise $${INSTANCE_IP} -retry-join=${module.consul.server_address} -data-dir=/opt/consul/data -client 0.0.0.0"
  }
}

###################### Instances part ######################

resource "aws_instance" "master" {
  connection {
    user        = "${var.instance_user}"
    private_key = "${file("${var.key_path}")}"
  }

  provisioner "file" {
    source      = "${path.module}/consul/scripts/debian_upstart.conf"
    destination = "/tmp/upstart.conf"
  }

  provisioner "file" {
    content     = "${template_file.consul_agent_install.rendered}"
    destination = "/tmp/install.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install.sh",
      "/tmp/install.sh",
    ]
  }

  provisioner "remote-exec" {
    scripts = [
      "${path.module}/consul/scripts/service.sh",
      "${path.module}/consul/scripts/ip_tables.sh",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get install dnsmasq",
      "echo \"server=/consul/127.0.0.1#8600\" > /etc/dnsmasq.d/10-consul",
      "dig consul.service.consul",
    ]
  }

  tags {
    Name = "splunk_master"
  }

  root_block_device {
    volume_size           = 1000
    delete_on_termination = true
  }

  ami                    = "${var.ami}"
  instance_type          = "${var.instance_type_indexer}"
  key_name               = "${var.key_name}"
  subnet_id              = "${element(module.stack.external_subnets, "0")}"
  user_data              = "${template_file.user_data_master.rendered}"
  vpc_security_group_ids = ["${aws_security_group.all.id}"]
}

resource "consul_service" "master" {
  address = "${aws_instance.master.private_ip}"
  name    = "cluster-master"
  port    = 8089
}

resource "aws_instance" "deploymentserver" {
  connection {
    user        = "${var.instance_user}"
    private_key = "${file("${var.key_path}")}"
  }

  provisioner "file" {
    source      = "${path.module}/consul/scripts/debian_upstart.conf"
    destination = "/tmp/upstart.conf"
  }

  provisioner "file" {
    content     = "${template_file.consul_agent_install.rendered}"
    destination = "/tmp/install.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install.sh",
      "/tmp/install.sh",
    ]
  }

  provisioner "remote-exec" {
    scripts = [
      "${path.module}/consul/scripts/service.sh",
      "${path.module}/consul/scripts/ip_tables.sh",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get install dnsmasq",
      "echo \"server=/consul/127.0.0.1#8600\" > /etc/dnsmasq.d/10-consul",
      "dig consul.service.consul",
    ]
  }

  tags {
    Name = "splunk_deploymentserver"
  }

  root_block_device {
    volume_size           = 1000
    delete_on_termination = true
  }

  ami                    = "${var.ami}"
  instance_type          = "${var.instance_type_indexer}"
  key_name               = "${var.key_name}"
  private_ip             = "${var.deploymentserver_ip}"
  subnet_id              = "${element(module.stack.external_subnets, "0")}"
  user_data              = "${template_file.user_data_deploymentserver.rendered}"
  vpc_security_group_ids = ["${aws_security_group.all.id}"]
}

resource "consul_service" "deploymentserver" {
  address = "${aws_instance.deploymentserver.private_ip}"
  name    = "deployment-server"
  port    = 8089
}

resource "aws_instance" "indexer" {
  count = "${var.count_indexer}"

  connection {
    user        = "${var.instance_user}"
    private_key = "${file("${var.key_path}")}"
  }

  provisioner "file" {
    source      = "${path.module}/consul/scripts/debian_upstart.conf"
    destination = "/tmp/upstart.conf"
  }

  provisioner "file" {
    content     = "${template_file.consul_agent_install.rendered}"
    destination = "/tmp/install.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install.sh",
      "/tmp/install.sh",
    ]
  }

  provisioner "remote-exec" {
    scripts = [
      "${path.module}/consul/scripts/service.sh",
      "${path.module}/consul/scripts/ip_tables.sh",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get install dnsmasq",
      "echo \"server=/consul/127.0.0.1#8600\" > /etc/dnsmasq.d/10-consul",
      "dig consul.service.consul",
    ]
  }

  tags {
    Name = "splunk_indexer"
  }

  root_block_device {
    volume_size           = 1000
    delete_on_termination = true
  }

  ami                    = "${var.ami}"
  instance_type          = "${var.instance_type_indexer}"
  key_name               = "${var.key_name}"
  subnet_id              = "${element(module.stack.external_subnets, count.index)}"
  user_data              = "${template_file.user_data_indexer.rendered}"
  vpc_security_group_ids = ["${aws_security_group.all.id}"]
}

resource "consul_service" "indexer" {
  count = "${var.count_indexer}"

  address = "${element(aws_instance.indexer.*.private_ip, count.index)}"
  name    = "indexer-${count.index}"
  port    = 8089
}

resource "aws_instance" "searchhead" {
  count = "${var.asg_searchhead_desired}"

  connection {
    user        = "${var.instance_user}"
    private_key = "${file("${var.key_path}")}"
  }

  provisioner "file" {
    source      = "${path.module}/consul/scripts/debian_upstart.conf"
    destination = "/tmp/upstart.conf"
  }

  provisioner "file" {
    content     = "${template_file.consul_agent_install.rendered}"
    destination = "/tmp/install.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install.sh",
      "/tmp/install.sh",
    ]
  }

  provisioner "remote-exec" {
    scripts = [
      "${path.module}/consul/scripts/service.sh",
      "${path.module}/consul/scripts/ip_tables.sh",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get install dnsmasq",
      "echo \"server=/consul/127.0.0.1#8600\" > /etc/dnsmasq.d/10-consul",
      "dig consul.service.consul",
    ]
  }

  tags {
    Name = "splunk_searchhead"
  }

  root_block_device {
    volume_size           = 1000
    delete_on_termination = true
  }

  ami                    = "${var.ami}"
  instance_type          = "${var.instance_type_searchhead}"
  key_name               = "${var.key_name}"
  subnet_id              = "${element(module.stack.external_subnets, count.index)}"
  user_data              = "${template_file.user_data_searchhead.rendered}"
  vpc_security_group_ids = ["${aws_security_group.all.id}"]
}

resource "consul_service" "searchhead" {
  count = "${var.asg_searchhead_desired}"

  address = "${element(aws_instance.searchhead.*.private_ip, count.index)}"
  name    = "searchhead-${count.index}"
  port    = 8089
}
