
variable "resource_group_name" {
  type        = string
  default     = "sre-networking-rg"
}

variable "region" {
  description = "The region to create the EKS cluster in"
  type        = string
}
variable "vnet_name" {
  description = "The name of the virtual network to create the EKS cluster in"
  type        = string
  default     = "sre-vnet1"
}

variable "vnet_cidr" {
  description = "The CIDR of the virtual network to create the EKS cluster in"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_system" {
  description = "Subnet for system node group"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "aks_subnet_user" {
  description = "Subnet for user node group"
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "allowed_ports" {
  description = "Allowed ports for nodes"
  type        = list(number)
  default     = [22, 80, 443]
}