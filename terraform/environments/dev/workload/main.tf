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

module "eks" {
  source = "../../../modules/eks"

  project           = var.project
  environment       = var.environment
  subnet_ids        = data.terraform_remote_state.network.outputs.private_subnet_ids
  cluster_sg_id     = data.terraform_remote_state.network.outputs.eks_cluster_sg_id
  node_sg_id        = data.terraform_remote_state.network.outputs.eks_node_sg_id
  api_allowed_cidrs = [var.my_ip]

  # Module-level: Terraform cannot depends_on a variable. NAT is minutes; cluster is ~10.
  depends_on = [aws_route.private_default]
}

# RDS and ALB are later stories. Destroy this root after a session.
