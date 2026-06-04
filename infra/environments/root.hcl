


generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
  
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }

  }
}



provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    
  }
}

provider "azurerm" {
  features {}
}
EOF
}

#Defining Global tags 
locals {
  environment = basename(path_relative_to_include()) 

  global_tags = {
    Project     = "SRE-PROJECT"
    ManagedBy   = "DevOps_Team"
    Environment = local.environment
  }
}
