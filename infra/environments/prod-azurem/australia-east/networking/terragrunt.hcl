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
  source = "../../../../modules/azure/networking"

  extra_arguments "vars_file" {
    commands = ["apply", "plan", "validate", "destroy"]
    arguments = ["-var-file=${dirname(get_terragrunt_dir())}/prod-austr.tfvars"]
  }
}
