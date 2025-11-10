data "terraform_remote_state" "vpc" {
  backend = "local"

  config = {
    path = "../002.vpc/terraform.tfstate"
  }
}
