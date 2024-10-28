variable "parent_cidr" {
  description = "The CIDR block for the VNet"
  type        = string
}

variable "subnets" {
  description = "Map of subnet names to their respective CIDR blocks or mask sizes"
  type        = map(any)

  validation {
    condition = (
      alltrue([for _, v in var.subnets : can(cidrsubnet(v, 0, 0))]) || 
      alltrue([for _, v in var.subnets : can(tonumber(v)) && tonumber(v) >= 29])
    )
    error_message = "Subnets variable must contain either all CIDR blocks or all mask sizes, not a mix of both. If using mask sizes, each size must be at least /29."
  }
}

locals {
  # Check if all values are CIDR blocks
  all_are_cidr = alltrue([for _, cidr in var.subnets : can(cidrsubnet(cidr, 0, 0))])

  # Conditionally call cidr_calc module if values are mask sizes
  final_subnets = local.all_are_cidr ? var.subnets : module.cidr_calc.subnets
}

module "cidr_calc" {
  source      = "./cidr_calc_module"
  subnets     = var.subnets
  parent_cidr = var.parent_cidr

  # Call the module only if subnets contains mask sizes
  count = local.all_are_cidr ? 0 : 1
}

output "subnets" {
  value = local.final_subnets
}
