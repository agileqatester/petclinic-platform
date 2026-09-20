output "nat_instance_id" {
  description = "NAT instance ID"
  value       = module.nat.instance_id
}

output "nat_public_ip" {
  description = "NAT instance Elastic IP"
  value       = module.nat.public_ip
}

output "nat_security_group_id" {
  description = "NAT instance security group ID"
  value       = module.nat.security_group_id
}

output "nat_network_interface_id" {
  description = "NAT primary ENI (private default routes)"
  value       = module.nat.network_interface_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "IAM OIDC provider ARN"
  value       = module.eks.oidc_provider_arn
}

output "eks_oidc_provider_url" {
  description = "OIDC issuer URL without https://"
  value       = module.eks.oidc_provider_url
}

output "eks_node_group_name" {
  description = "Managed node group name"
  value       = module.eks.node_group_name
}

output "eks_update_kubeconfig" {
  description = "Configure kubectl for this cluster"
  value       = module.eks.update_kubeconfig
}

output "rds_endpoint" {
  description = "RDS MySQL hostname"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS MySQL port"
  value       = module.rds.port
}

output "rds_instance_id" {
  description = "RDS instance identifier"
  value       = module.rds.db_instance_id
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN for petclinic/dev/rds-credentials"
  value       = module.rds.secret_arn
  sensitive   = true
}

output "lbc_role_arn" {
  description = "IRSA role ARN for aws-load-balancer-controller (helm install after E-3 apply)"
  value       = aws_iam_role.lbc.arn
}
