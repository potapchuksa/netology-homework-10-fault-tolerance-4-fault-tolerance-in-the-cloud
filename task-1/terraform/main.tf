terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

provider "yandex" {
  zone = "ru-central1-b"
}

resource "yandex_compute_instance" "vm" {
  count = 2

  name = "vm-${count.index + 1}"
  hostname = "vm-${count.index + 1}"
  platform_id = "standard-v1"

  resources {
    cores  = 2
    memory = 1
    core_fraction = 20 
  }

  boot_disk {
    initialize_params {
      image_id = "fd80bm0rh4rkepi5ksdi" # Ubuntu 22.04 LTS
      type     = "network-hdd"
      size     = 8
    }
  }

  scheduling_policy { preemptible = true }

  network_interface {
    subnet_id  = yandex_vpc_subnet.my_subnet.id
    nat        = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
}

resource "yandex_vpc_network" "my_network" {
  name = "my_network"
}

resource "yandex_vpc_subnet" "my_subnet" {
  name = "my_subnet"
  network_id = yandex_vpc_network.my_network.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}


resource "yandex_lb_target_group" "my_group" {
  name = "my-group"

  dynamic "target" {
    for_each = yandex_compute_instance.vm
    content {
      subnet_id = yandex_vpc_subnet.my_subnet.id
      address = target.value.network_interface.0.ip_address
    }
  }
}

resource "yandex_lb_network_load_balancer" "my_balancer" {
  name = "my-balancer"
  deletion_protection = "false"

  listener {
    name = "my-lb"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.my_group.id
    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

resource "local_file" "inventory" {
  content  = <<-XYZ
  [webservers]
  ${yandex_compute_instance.vm[0].network_interface.0.nat_ip_address}
  ${yandex_compute_instance.vm[1].network_interface.0.nat_ip_address}

  [webservers:vars]
  ansible_user=ubuntu
  ansible_ssh_private_key_file=~/.ssh/id_rsa
  XYZ
  filename = "../ansible/hosts.ini"
}
