/*
This Terraform configuration is designed to dynamically calculate and generate subnet CIDR blocks within a specified VNet, based on a provided parent CIDR block and a map of subnets with their respective CIDR sizes. The primary problem this configuration addresses is the need to create multiple subnets within a VNet while ensuring that each subnet is properly spaced and does not overlap with others, even as the number and sizes of subnets vary.

The purpose of this configuration is to automatically calculate the correct offsets for each subnet and generate the corresponding CIDR blocks in a way that ensures efficient IP allocation. The subnets are first sorted by their mask size, ensuring that larger subnets (those with more IP addresses) are created first. This approach minimizes the risk of IP address wastage and ensures that the available IP space is used optimally.

The process works as follows:
1. The mask size of the parent CIDR block is extracted and used as a base for calculating the subnet CIDRs.
2. Each subnet's CIDR size is mapped to the number of IP addresses it can contain.
3. The subnets are sorted by their CIDR size (mask size) in descending order, so that subnets with the most IP addresses are allocated first.
4. The configuration calculates the correct offset for each subnet based on the cumulative IP addresses of all preceding subnets.
5. Finally, the CIDR block for each subnet is generated based on its offset and size, and the results are outputted for use in deploying the subnets within the VNet.

This configuration ensures that subnets are created efficiently and without overlap, making it easier to manage IP space within a VNet.
*/

variable "parent_cidr" {
  description = "The CIDR block for the VNet"
  type        = string
  default     = "10.232.0.128/25"
}

variable "subnets" {
  description = "Map of subnet names to their respective CIDR block sizes"
  type        = map(number)
  default = {
    "test"   = 27,
    "test2"          = 26,
  }
}

locals {
  # Extracting the mask size (e.g., /25) from the parent CIDR block
  starting_vnet_mask_size = tonumber(split("/", var.parent_cidr)[1])

  # Dynamically calculate the number of IP addresses each subnet can contain using the formula 2^(32 - n), where n is the CIDR number
  ip_mask_map = { for size in range(20, 33) : format("%d", size) => pow(2, 32 - size) }

  # Create a list of subnet names sorted by mask size in descending order (largest to smallest)
  sorted_subnet_names = sort([for subnet, size in var.subnets : format("%02d:%s", -size, subnet)])

  # Transform sorted_subnet_names into a list of subnet names only, ordered by mask size
  sorted_subnets = [for item in local.sorted_subnet_names : element(split(":", item), 1)]

  # Calculating the offset for each subnet based on the cumulative IP addresses of all preceding subnets
  subnet_offsets = {
    for subnet in local.sorted_subnets :
    subnet => length([
      for s in local.sorted_subnets : 
      local.ip_mask_map[format("%d", var.subnets[s])] # Retrieve the number of IP addresses in the preceding subnets
      if index(local.sorted_subnets, s) < index(local.sorted_subnets, subnet) # Only consider subnets that come before the current one
    ]) > 0 ? ceil(
      sum([
        for s in local.sorted_subnets : 
        local.ip_mask_map[format("%d", var.subnets[s])] # Sum the IP addresses of all preceding subnets
        if index(local.sorted_subnets, s) < index(local.sorted_subnets, subnet) # Only sum for subnets that come before the current one
      ]) / local.ip_mask_map[format("%d", var.subnets[subnet])]
    ) : 0 # If there are no preceding subnets, the offset is 0
  }

  # Calculating the CIDR block for each subnet based on its offset and size
  subnet_cidrs = {
    for subnet in local.sorted_subnets :
    subnet => cidrsubnet(
      var.parent_cidr, 
      var.subnets[subnet] - local.starting_vnet_mask_size, # Calculate the new mask size for the subnet
      local.subnet_offsets[subnet] # Apply the calculated offset
    )
  }
}

# Outputting the calculated offsets for each subnet
output "subnets_offsets" {
  value = local.subnet_offsets
}

# Outputting the final calculated CIDR blocks for each subnet
output "subnets" {
  value = local.subnet_cidrs
}
