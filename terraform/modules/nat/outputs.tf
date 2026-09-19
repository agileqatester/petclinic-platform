output "instance_id" {
  description = "NAT instance ID"
  value       = aws_instance.this.id
}

output "network_interface_id" {
  description = "Primary ENI ID for private default routes"
  value       = aws_instance.this.primary_network_interface_id
}

output "security_group_id" {
  description = "NAT instance security group ID"
  value       = aws_security_group.this.id
}

output "public_ip" {
  description = "Elastic IP of the NAT instance"
  value       = aws_eip.this.public_ip
}
