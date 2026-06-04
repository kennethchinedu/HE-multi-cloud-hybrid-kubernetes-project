include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  service_name = basename(get_terragrunt_dir())
  environment  = basename(dirname(get_terragrunt_dir()))

  tags_map = {
    Environment = local.environment
    Project     = "SRE-PROJECT"
    Service     = local.service_name
  }
}

terraform {
  source = "../../../../modules/azure/aks"

  extra_arguments "vars_file" {
    commands  = ["plan", "apply", "destroy", "validate"]
    arguments = ["-var-file=${dirname(get_terragrunt_dir())}/prod-austr.tfvars"]
  }
}

dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    vnet_name           = "mock-vnet"
    resource_group_name = "mock-rg"
    subnet_system_id    = "/subscriptions/mock/resourceGroups/mock/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/mock-subnet-system"
    subnet_user_id      = "/subscriptions/mock/resourceGroups/mock/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/mock-subnet-user"
  }

  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
}

inputs = {
  vnet_name           = dependency.networking.outputs.vnet_name
  subnet_system_id    = dependency.networking.outputs.subnet_system_id
  subnet_user_id      = dependency.networking.outputs.subnet_user_id
  resource_group_name = dependency.networking.outputs.resource_group_name
}

