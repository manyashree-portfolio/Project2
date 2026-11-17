variable "name" {
  description = "Name prefix for the resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "tgw_asn" {
  description = "Amazon-side BGP ASN of the Transit Gateway"
  type        = number
}

variable "endpoint_cidrs" {
  description = "CIDR blocks allowed to use the VPC interface endpoints"
  type        = list(string)
}
