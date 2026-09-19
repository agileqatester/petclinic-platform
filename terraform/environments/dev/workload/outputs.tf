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
