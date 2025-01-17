data template_file "userdata" {
  template = file("${path.module}/userdata.yaml")
  vars = {
    username           = var.instance_userdata_username
    ssh_public_key     = var.instance_userdata_ssh_public_key
  }
}

resource "yandex_resourcemanager_folder" "folder" {
  cloud_id    = "${var.cloud_id}"
  name        = "catgpt"
  description = "sale of goods and services"
}

locals {
  service-accounts = toset([
    "catgpt-sa",
    "catgpt-ig-sa",
  ])
  catgpt-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor",
  ])
  catgpt-ig-sa-roles = toset([
    "compute.editor",
    "iam.serviceAccounts.user",
    "load-balancer.admin",
    "vpc.publicAdmin",
    "vpc.user",
  ])
}

resource "yandex_vpc_network" "foo" {}

resource "yandex_vpc_subnet" "foo" {
  zone           = "${var.root_zone}"
  network_id     = yandex_vpc_network.foo.id
  v4_cidr_blocks = ["10.5.0.0/24"]
}

resource "yandex_container_registry" "registry1" {
  name = "registry1"
}


resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = "${local.folder_id}-${each.key}"
}
resource "yandex_resourcemanager_folder_iam_member" "catgpt-roles" {
  for_each  = local.catgpt-sa-roles
  folder_id = yandex_resourcemanager_folder.folder.id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-sa"].id}"
  role      = each.key
}
resource "yandex_resourcemanager_folder_iam_member" "catgpt-ig-roles" {
  for_each  = local.catgpt-ig-sa-roles
  folder_id = yandex_resourcemanager_folder.folder.id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-ig-sa"].id}"
  role      = each.key
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}

resource "yandex_compute_instance_group" "catgpt" {
  depends_on = [
    yandex_resourcemanager_folder_iam_member.catgpt-ig-roles
  ]
  name               = "catgpt"
  service_account_id = yandex_iam_service_account.service-accounts["catgpt-ig-sa"].id
  allocation_policy {
    zones = ["ru-central1-a"]
  }
  deploy_policy {
    max_unavailable = 1
    max_creating    = 2
    max_expansion   = 2
    max_deleting    = 2
  }
  scale_policy {
    fixed_scale {
      size = 2
    }
  }
  instance_template {
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["catgpt-sa"].id
    resources {
      cores         = 2
      memory        = 1
      core_fraction = 5
    }
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      network_id = yandex_vpc_network.foo.id
      subnet_ids = ["${yandex_vpc_subnet.foo.id}"]
      nat        = true
    }
    boot_disk {
      initialize_params {
        type     = "network-hdd"
        size     = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    metadata = {
      docker-compose = templatefile(
        "${path.module}/docker-compose.yaml",
        {
          folder_id   = "${yandex_resourcemanager_folder.folder.id}",
          registry_id = "${yandex_container_registry.registry1.id}",
        }
      )
      user-data = data.template_file.userdata.rendered
    }
  }
  load_balancer {
    target_group_name = "catgpt"
  }
}

resource "yandex_lb_network_load_balancer" "lb-catgpt" {
  name = "catgpt"

  listener {
    name        = "cat-listener"
    port        = 80
    target_port = 8080
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.catgpt.load_balancer[0].target_group_id

    healthcheck {
      name = "http"
      http_options {
        port = 8080
        path = "/ping"
      }
    }
  }
}