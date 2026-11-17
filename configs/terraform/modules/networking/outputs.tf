output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "transit_gateway_id" {
  value = aws_ec2_transit_gateway.this.id
}
