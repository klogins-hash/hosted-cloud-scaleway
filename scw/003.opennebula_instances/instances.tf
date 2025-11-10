data "scaleway_baremetal_os" "ubuntu_noble" {
  zone    = var.zone
  name    = "Ubuntu"
  version = "24.04 LTS (Noble Numbat)"
}

data "scaleway_baremetal_os" "debian_bookworm" {
  zone    = var.zone
  name    = "Debian"
  version = "12 (Bookworm)"
}


resource "scaleway_iam_ssh_key" "temp_ssh_key" {
  name       = "tf generated ssh_key"
  public_key = chomp(tls_private_key.ssh.public_key_openssh)
}

data "scaleway_vpc_private_network" "private_network" {
  private_network_id = data.terraform_remote_state.vpc.outputs.private_network_id
}

data "scaleway_vpc_private_network" "private_network_vmtovm" {
  private_network_id = data.terraform_remote_state.vpc.outputs.vmtovm_private_network_id
}

data "scaleway_baremetal_offer" "EM-A610R-NVME" {
  zone                = var.zone
  name                = "EM-A610R-NVME"
  subscription_period = "hourly"
}

data "scaleway_baremetal_option" "private_network" {
  zone = var.zone
  name = "Private Network"
}

resource "scaleway_baremetal_server" "opennebula-web" {
  name            = "opennebula-web"
  zone            = var.zone
  offer           = data.scaleway_baremetal_offer.EM-A610R-NVME.offer_id
  os              = data.scaleway_baremetal_os.ubuntu_noble.os_id
  ssh_key_ids     = [scaleway_iam_ssh_key.temp_ssh_key.id]
  private_network {
    id = data.scaleway_vpc_private_network.private_network.id
  }
  private_network {
    id = data.scaleway_vpc_private_network.private_network_vmtovm.id
  }
  options {
    id = data.scaleway_baremetal_option.private_network.option_id
  }
}

resource "scaleway_flexible_ip" "opennebula-web-public-ip" {
  zone = var.zone
  description = "opennebula-web-public-ip"
  server_id = scaleway_baremetal_server.opennebula-web.id
}

resource "scaleway_flexible_ip_mac_address" "opennebula-web-public-ip-mac" {
  flexible_ip_id = scaleway_flexible_ip.opennebula-web-public-ip.id
  type           = "kvm"
}

resource "scaleway_baremetal_server" "opennebula-worker" {
  count           = var.worker_count
  name            = "opennebula-worker-${count.index}"
  zone            = var.zone
  offer           = data.scaleway_baremetal_offer.EM-A610R-NVME.offer_id
  os              = data.scaleway_baremetal_os.ubuntu_noble.os_id
  ssh_key_ids     = [scaleway_iam_ssh_key.temp_ssh_key.id]
  private_network {
    id = data.scaleway_vpc_private_network.private_network.id
  }
  private_network {
    id = data.scaleway_vpc_private_network.private_network_vmtovm.id
  }
  options {
    id = data.scaleway_baremetal_option.private_network.option_id
  }
}

resource "scaleway_flexible_ip" "opennebula-worker-public-ip" {
  count         = var.worker_count
  description   = "opennebula-worker-public-ip-${count.index}"
  zone          = var.zone
  server_id     = scaleway_baremetal_server.opennebula-worker[count.index].id
}

resource "scaleway_flexible_ip_mac_address" "opennebula-worker-public-ip-mac" {
  count         = var.worker_count
  flexible_ip_id = scaleway_flexible_ip.opennebula-worker-public-ip[count.index].id
  type           = "kvm"
}
