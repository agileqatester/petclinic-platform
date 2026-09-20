data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket         = "petclinic-terraform-state-${var.aws_account_id}"
    key            = "petclinic/${var.environment}/network/terraform.tfstate"
    region         = var.aws_region
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
    profile        = "petclinic"
  }
}

module "nat" {
  source = "../../../modules/nat"

  project           = var.project
  environment       = var.environment
  vpc_id            = data.terraform_remote_state.network.outputs.vpc_id
  vpc_cidr          = data.terraform_remote_state.network.outputs.vpc_cidr
  public_subnet_ids = data.terraform_remote_state.network.outputs.public_subnet_ids
  client_security_group_ids = [
    data.terraform_remote_state.network.outputs.eks_node_sg_id,
  ]
  instance_type = var.nat_instance_type
  enable_ssm    = true
}

resource "aws_route" "private_default" {
  count = length(data.terraform_remote_state.network.outputs.private_route_table_ids)

  route_table_id         = data.terraform_remote_state.network.outputs.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.nat.network_interface_id
}
