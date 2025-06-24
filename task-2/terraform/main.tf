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

resource "yandex_compute_instance_group" "my-group" {
  name = "fixed-ig-with-balancer"
  service_account_id = "aje6ms1tbm6bleb598h7"
  instance_template {
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
      subnet_ids  = [yandex_vpc_subnet.my_subnet.id]
      nat        = true
    }

    metadata_options {
      gce_http_endpoint    = 0
      gce_http_token       = 0
    }

    metadata = {
      ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
      user-data = file("metadata.yaml")
    }
  }

  scale_policy {
    fixed_scale {
      size = 2
    }
  }

  allocation_policy {
    zones = ["ru-central1-b"]
  }

  deploy_policy {
    max_unavailable = 1
    max_expansion   = 0
  }

  load_balancer {
    target_group_name = "my-group"
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
    target_group_id = yandex_compute_instance_group.my-group.load_balancer.0.target_group_id
    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}
