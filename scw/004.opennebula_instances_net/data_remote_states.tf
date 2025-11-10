data "terraform_remote_state" "instances" {
  backend = "local"

  config = {
    path = "../003.opennebula_instances/terraform.tfstate"
  }
}

data "terraform_remote_state" "vpc" {
  backend = "local"

  config = {
    path = "../002.vpc/terraform.tfstate"
  }
}
