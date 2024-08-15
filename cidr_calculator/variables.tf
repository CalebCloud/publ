variable "parent_cidr" {
  description = "The CIDR block for the VNet"
  type        = string
}

variable "subnets" {
  description = "Map of subnet names to their respective CIDR block sizes"
  type        = map(number)
}
