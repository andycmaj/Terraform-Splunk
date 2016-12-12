# Specify the provider and access details
provider "aws" {
  region = "${var.region}"
}

resource "aws_instance" "server" {
  ami             = "ami-b22981d2"
  instance_type   = "${var.instance_type}"
  key_name        = "${var.key_name}"
  count           = "${var.servers}"
  security_groups = ["${aws_security_group.consul.name}"]

  connection {
    user        = "ubuntu"
    private_key = "${file("${var.key_path}")}"
  }

  #Instance tags
  tags {
    Name       = "${var.tagName}-${count.index}"
    ConsulRole = "Server"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.servers} > /tmp/consul-server-count",
      "echo ${aws_instance.server.0.private_dns} > /tmp/consul-server-addr",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/scripts/debian_upstart.conf"
    destination = "/tmp/upstart.conf"
  }

  provisioner "file" {
    content     = "${template_file.server_install.rendered}"
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
      "${path.module}/scripts/service.sh",
      "${path.module}/scripts/ip_tables.sh",
    ]
  }
}

resource "template_file" "server_install" {
  template = "${path.module}/scripts/install.tpl"

  vars {
    consul_params = "-server -bootstrap-expect=$${SERVER_COUNT} -join=$${CONSUL_JOIN} -data-dir=/opt/consul/data -ui -client 0.0.0.0"
  }
}

resource "aws_security_group" "consul" {
  name        = "consul_ubuntu"
  description = "Consul internal traffic + maintenance."

  // These are for internal traffic
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "udp"
    self      = true
  }

  // These are for maintenance
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // Web/api access
  ingress {
    from_port   = 8500
    to_port     = 8500
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // This is for outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
