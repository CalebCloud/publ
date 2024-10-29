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


variable "subnets" {
  description = "Map of subnet names to either CIDR blocks or subnet masks"
  type        = map(any)
  default     = {
    # Example input; replace as needed
    "example-subnet-1" = "10.232.84.0/24"
    "example-subnet-2" = 28
  }

  validation {
    condition = (
      alltrue([for v in values(var.subnets) : can(cidrhost(v, 0))]) || 
      alltrue([for v in values(var.subnets) : v >= 16 && v <= 32])
    ) && !(
      anytrue([for v in values(var.subnets) : can(cidrhost(v, 0))]) &&
      anytrue([for v in values(var.subnets) : v >= 16 && v <= 32])
    )
    error_message = "All values must be either valid CIDR blocks or subnet masks, but not a mixture of both."
  }
}

variable "subnets" {
  description = "Map of subnet names to either CIDR blocks or subnet masks"
  type        = map(any)
  default     = {
    # Example input; replace as needed
    "example-subnet-1" = "10.232.84.0/24"
    "example-subnet-2" = 28
  }

  validation {
    condition = (
      alltrue([for v in values(var.subnets) : can(cidrhost(v, 0))]) || 
      alltrue([for v in values(var.subnets) : v >= 16 && v <= 32])
    ) && !(
      anytrue([for v in values(var.subnets) : can(cidrhost(v, 0))]) &&
      anytrue([for v in values(var.subnets) : v >= 16 && v <= 32])
    )
    error_message = "All values must be either valid CIDR blocks or subnet masks, but not a mixture of both."
  }
}

variable "subnets" {
  description = "Map of subnet names to their respective CIDR or mask sizes"
  type        = map(any)
  default     = {
    "example-subnet-1" = "10.0.0.0/24"
    "example-subnet-2" = 28
  }

  validation {
    condition = (
      alltrue([for _, v in var.subnets : can(cidrhost(v, 0))]) ||
      alltrue([for _, v in var.subnets : can(tonumber(v)) && tonumber(v) <= 29])
    ) && !(alltrue([for _, v in var.subnets : can(cidrhost(v, 0))]) &&
            alltrue([for _, v in var.subnets : can(tonumber(v)) && tonumber(v) <= 29]))

    error_message = "The 'subnets' variable must contain either all CIDR blocks or all mask sizes, not both."
  }
}

locals {
  use_masks = alltrue([for _, v in var.subnets : can(tonumber(v)) && tonumber(v) <= 29])
}
