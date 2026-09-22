module "vpc" {
  source = "../../../modules/vpc"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "ecr" {
  source = "../../../modules/ecr"

  project     = var.project
  environment = var.environment
  service_names = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server",
  ]
  image_tag_mutability = "MUTABLE"
}

# Keep stack: VPC + ECR + GitHub OIDC (ADR-0020). NAT default route is added by the workload root.
