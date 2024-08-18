/*
This advanced Terraform configuration dynamically calculates and assigns CIDR blocks to new subnets within a specified Virtual Network (VNet), integrating seamlessly with pre-existing subnet configurations. It leverages a provided parent CIDR block and a user-defined map of desired subnets, specified by their CIDR sizes or directly as CIDR blocks for existing subnets. The configuration's primary aim is to ensure optimal utilization of the IP address space within the VNet by avoiding overlap and aligning subnet boundaries accurately.

Key Features:
1. Integration with Existing Infrastructure: Automatically identifies and integrates with existing subnets within the VNet, ensuring that new subnets are allocated only where IP space is available.
2. Dynamic CIDR Allocation: Uses a strategic sorting and allocation system that prioritizes larger subnets to minimize IP address wastage. This system adapts to varying subnet sizes and dynamically adjusts to the existing network landscape.
3. Efficient IP Management: Ensures that each new subnet is allocated efficiently with correct offsets to maintain contiguous and non-overlapping IP ranges.
4. Flexible Configuration: Supports dynamic inputs where subnet details can be pre-defined or calculated based on real-time data from the VNet, offering flexibility and adaptability to changing network requirements.

Operational Process:
1. Extract the mask size from the parent CIDR block to establish a baseline for subnet calculations.
2. Identify existing subnets from a structured data source and map their CIDR blocks to ensure they are recognized during the allocation process.
3. Filter and prepare a list of new subnets, excluding any that already exist in the VNet.
4. Sort all new subnets by their mask size in descending order to prioritize larger subnets, ensuring efficient space utilization.
5. Calculate the correct offset for each new subnet by considering the cumulative IP addresses utilized by existing and previously calculated new subnets.
6. Generate and assign CIDR blocks for new subnets based on their calculated offsets, ensuring they fit seamlessly within the parent CIDR block without overlapping with existing subnets.
7. Output the newly calculated subnet CIDR blocks for implementation and deployment within the VNet infrastructure.

This configuration is designed to serve as a robust solution for managing complex VNet environments, ensuring scalable, efficient, and error-free subnet deployment. It supports ongoing network expansions and adaptations, making it ideal for dynamic cloud environments and large-scale infrastructure projects.
*/


variable "parent_cidr" {
  description = "The CIDR block for the VNet"
  type        = string
  default     = "10.232.9.0/24"
}

variable "subnets" {
  description = "Map of subnet names to their respective CIDR block sizes"
  type        = map(number)
  default = {
    "test-app"         = 27,
    "test-gw"          = 28,
    "test-pe"          = 27,
    "test-sh"          = 27,
    "test-new"          = 28,
    "test-new-small"          = 30,
    "test-new-xbig"          = 27,
  }
}

# Testing
locals {
  # Example testing data structure (abbreviated for clarity)
  cidr_calc_testing_data = {
    subnet_data = [
      {
        "test-app" = {
          address_prefix = "10.232.9.0/27"
        },
        "test-db" = {
          address_prefix = "10.232.9.96/28"
        },
        "test-gw" = {
          address_prefix = "10.232.9.112/28"
        },
        "test-pe" = {
          address_prefix = "10.232.9.32/27"
        },
        "test-sh" = {
          address_prefix = "10.232.9.64/27"
        }
      }
    ]
  }

  # Extracting subnet names and their corresponding CIDR blocks
  existing_subnets = merge([
    for subnet_list in local.cidr_calc_testing_data.subnet_data : 
    { for subnet_name, subnet_details in subnet_list : subnet_name => subnet_details.address_prefix }
  ]...)
  # Like
  # existing_subnets = {
  #   "test-app" = "10.232.9.0/27"
  #   "test-db" = "10.232.9.96/28"
  #   "test-gw" = "10.232.9.112/28"
  #   "test-pe" = "10.232.9.32/27"
  #   "test-sh" = "10.232.9.64/27"
  # }

  # Determining which subnets to process for CIDR allocation or retention
  subnets_to_manage = {
    for subnet_name, cidr_or_mask in var.subnets : 
    subnet_name => contains(keys(local.existing_subnets), subnet_name) ? 
                   local.existing_subnets[subnet_name] : 
                   cidr_or_mask
  }
  # Like:
  # subnets_to_manage = {
  #   "test-app" = "10.232.9.0/27"
  #   "test-gw" = "10.232.9.112/28"
  #   "test-new" = 28
  #   "test-pe" = "10.232.9.32/27"
  #   "test-sh" = "10.232.9.64/27"
  # }

  # Subnets requiring new CIDR calculation
  # (Matching a subnet with passed mask)
  new_subnets = {
    for subnet_name, cidr_or_mask in local.subnets_to_manage :
    subnet_name => cidr_or_mask
    if length(regexall("^\\d+$", tostring(cidr_or_mask))) == 1  # Check if the value is just a number (mask size)
  }
  # Like:
  # new_subnets = {
  #   "test-new" = 28
  # }

  # Calculate total IPs from existing subnets
  total_ips_existing_subnets = sum([
    for cidr in values(local.existing_subnets) : pow(2, 32 - tonumber(split("/", cidr)[1]))
  ])
  # Like: 128

  # Extracting the mask size (e.g., /25) from the parent CIDR block
  starting_vnet_mask_size = tonumber(split("/", var.parent_cidr)[1])

  # Dynamically calculate the number of IP addresses each subnet can contain using the formula 2^(32 - n), where n is the CIDR number
  ip_mask_map = { for size in range(20, 33) : format("%d", size) => pow(2, 32 - size) }

  # Sort the filtered new subnet names by mask size in descending order (largest to smallest)
  sorted_new_subnet_names = sort([for subnet, size in local.new_subnets : format("%02d:%s", -size, subnet)])
  # Like
  # sorted_new_subnet_names = [
  #   + "-27:test-new-big",
  #   + "-28:test-new",
  #   + "-30:test-new-small",
  # ]

  # Transform sorted_new_subnet_names into a list of subnet names only, ordered by mask size
  sorted_new_subnets = [for item in local.sorted_new_subnet_names : element(split(":", item), 1)]

  # Calculating the offset for each new subnet based on the cumulative IP addresses of all preceding new subnets
  subnet_offsets = {
    for subnet in local.sorted_new_subnets :
    subnet => length([
      for s in local.sorted_new_subnets : 
      local.ip_mask_map[format("%d", local.subnets_to_manage[s])] # Retrieve the number of IP addresses in the preceding new subnets
      if s != subnet && index(local.sorted_new_subnets, s) < index(local.sorted_new_subnets, subnet) # Exclude current subnet and only include subnets that are sorted before the current one in the list
    ]) > 0 ? ceil(
      (sum([
        for s in local.sorted_new_subnets : 
        local.ip_mask_map[format("%d", local.subnets_to_manage[s])] # Sum the IP addresses of all preceding new subnets
        if s != subnet && index(local.sorted_new_subnets, s) < index(local.sorted_new_subnets, subnet) # Exclude current subnet and sum IP addresses only for subnets that are sorted before the current one
      ]) + local.total_ips_existing_subnets) / local.ip_mask_map[format("%d", local.subnets_to_manage[subnet])] # Calculate the offset by adding the total IPs from existing subnets to the summed IPs from preceding new subnets
    ) : (local.total_ips_existing_subnets > 0 ? local.total_ips_existing_subnets / local.ip_mask_map[format("%d", local.subnets_to_manage[subnet])] : 0) # If no preceding subnets, use total existing IPs to determine the offset or set to 0 if there are no existing IPs
  }
  # Ensure the first new subnet takes into account the existing IPs
  # adjusted_first_subnet_offset = local.total_ips_existing_subnets > 0 && length(local.sorted_new_subnets) > 0 ? ceil(local.total_ips_existing_subnets / local.ip_mask_map[format("%d", var.subnets[local.sorted_new_subnets[0]] )]) : 0

  # Adjust the offset for the first new subnet
  # subnet_offsets_adjusted = {
  #   for subnet in local.sorted_new_subnets :
  #   subnet => subnet == local.sorted_new_subnets[0] ? local.adjusted_first_subnet_offset : local.subnet_offsets[subnet]
  # }
  # Like: 
  # subnets_offsets_for_newly_created_subnets = {
  #   "test-new" = 8
  # }

  # Adjust the CIDR calculation to use the adjusted offsets
  subnet_cidrs = {
    for subnet in local.sorted_new_subnets :
    subnet => cidrsubnet(
      var.parent_cidr, 
      local.new_subnets[subnet] - local.starting_vnet_mask_size,
      local.subnet_offsets[subnet]
    )
  }
  # Like
  # subnets = {
  #   "test-new" = "10.232.9.128/28"
  # }

  # Joining the cidr blocks generated for the new subnets with the existing subnet cidr blocks
  managed_subnet_cidrs = {
    for k, v in local.subnets_to_manage :
    k => contains(keys(local.subnet_cidrs), k) ? local.subnet_cidrs[k] : v
  }

}

# Outputting the final calculated CIDR blocks for each subnet
output "subnets" {
  value = local.subnet_cidrs
}

output "managed_subnet_cidrs" {
  value = local.managed_subnet_cidrs
}

output "subnets_to_manage" {
  value = local.subnets_to_manage
}