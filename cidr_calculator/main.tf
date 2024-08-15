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