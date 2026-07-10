output "public_subnet_ids" {
  description = "List of IDs of the public subnets created by this module."
  value       = aws_subnet.my-public-subnet-1[*].id
}

output "private_subnet_ids" {
  description = "List of IDs of the private subnets created by this module."
  value       = aws_subnet.my-private-subnet-1[*].id # <-- Correct resource name
}

output "public_route_table_id" {
  description = "The ID of the public route table."
  value       = aws_route_table.my-rtb.id
}

output "private_route_table_ids" {
  description = "The IDs of the private route table."
  value       = aws_route_table.my-private-rtb[*].id
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway."
  value       = aws_internet_gateway.my-igw.id
}

output "nat_gateway_ids" {
  description = "The IDs of the NAT Gateway."
  value       = aws_nat_gateway.my-nat[*].id
}
