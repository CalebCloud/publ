module "cidr_calculator" {
  source       = "../cidr_calculator"
  parent_cidr  = "10.232.0.128/25"
  subnets = {
    "test"   = 27,
    "test2"  = 26
  }
}

output "subnets" {
    value = module.cidr_calculator.subnets
}