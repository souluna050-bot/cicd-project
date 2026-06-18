terraform {
  required_providers {
    vkcs = {
      source = "vk-cs/vkcs"
      version = "~> 0.15"
    }
  }
}

variable "my_ip" {
  description = "Your IP for SSH"
  type        = string
  default     = "0.0.0.0/0"
}

variable "project_name" {
  default = "cicd-demo"
}

provider "vkcs" {}

resource "vkcs_networking_network" "main" {
  name = "${var.project_name}-network"
}

resource "vkcs_networking_subnet" "public" {
  name       = "${var.project_name}-subnet"
  network_id = vkcs_networking_network.main.id
  cidr       = "192.168.1.0/24"
  enable_dhcp = true
  allocation_pool {
    start = "192.168.1.10"
    end   = "192.168.1.200"
  }
}

resource "vkcs_networking_secgroup" "web" {
  name        = "${var.project_name}-sg"
  description = "Web security group"
}

resource "vkcs_networking_secgroup_rule" "web_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.my_ip
  security_group_id = vkcs_networking_secgroup.web.id
}

resource "vkcs_networking_secgroup_rule" "web_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = vkcs_networking_secgroup.web.id
}

data "vkcs_compute_keypair" "main" {
  name = "my-first-vm-9CKc3uIU"
}

data "vkcs_images_image" "ubuntu" {
  name        = "ubuntu-22-202602051629.gite7a38aaf"
  most_recent = true
}

resource "vkcs_blockstorage_volume" "web" {
  count = 2
  name  = "${var.project_name}-volume-${count.index + 1}"
  size  = 10
  image_id = data.vkcs_images_image.ubuntu.id
  volume_type = "ceph-ssd"
  availability_zone = "PA2"
}

resource "vkcs_compute_instance" "web" {
  count = 2

  name        = "${var.project_name}-web-${count.index + 1}"
  flavor_name = "STD3-1-1"
  key_pair    = data.vkcs_compute_keypair.main.name

  block_device {
    uuid                  = vkcs_blockstorage_volume.web[count.index].id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    name = vkcs_networking_network.main.name
  }

  security_groups = [vkcs_networking_secgroup.web.name]

  user_data = <<-EOF
    #!/bin/bash
    apt update
    apt install -y nginx
    echo "<h1>Web Server ${count.index + 1}</h1>" > /var/www/html/index.html
    systemctl enable nginx
    systemctl start nginx
  EOF
}

resource "vkcs_lb_loadbalancer" "main" {
  name          = "${var.project_name}-lb"
  vip_subnet_id = vkcs_networking_subnet.public.id
}

resource "vkcs_lb_listener" "http" {
  name            = "${var.project_name}-listener"
  protocol        = "HTTP"
  protocol_port   = 80
  loadbalancer_id = vkcs_lb_loadbalancer.main.id
}

resource "vkcs_lb_pool" "web" {
  name        = "${var.project_name}-pool"
  protocol    = "HTTP"
  lb_method   = "ROUND_ROBIN"
  listener_id = vkcs_lb_listener.http.id
}

resource "vkcs_lb_monitor" "web" {
  name        = "${var.project_name}-monitor"
  type        = "HTTP"
  delay       = 10
  timeout     = 5
  max_retries = 3
  url_path    = "/"
  pool_id     = vkcs_lb_pool.web.id
}

resource "vkcs_lb_member" "web" {
  count = 2

  name          = "${var.project_name}-member-${count.index + 1}"
  address       = vkcs_compute_instance.web[count.index].access_ip_v4
  protocol_port = 80
  pool_id       = vkcs_lb_pool.web.id
  subnet_id     = vkcs_networking_subnet.public.id
}

data "vkcs_networking_router" "existing" {
  name = "router_3732"
}

resource "vkcs_networking_router_interface" "public" {
  router_id = data.vkcs_networking_router.existing.id
  subnet_id = vkcs_networking_subnet.public.id
}
# Trigger pipeline
