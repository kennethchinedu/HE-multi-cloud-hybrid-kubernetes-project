variable "resource_group_name" {
  type        = string
}

variable "region" {
  type        = string
}

variable "vnet_name" {
  type        = string
}

variable "subnet_system_id" {
  type        = string
}

variable "subnet_user_id" {
  type        = string
}

variable "cluster_name" {
  type    = string
}

variable "cluster_version" {
  type    = string
}

variable "dns_prefix" {
  type    = string
  default = "sreaks"
}

variable "node_count" {
  type    = number
}

variable "vm_size" {
  type    = string
}

variable "sku_tier"{
  default = "Free"
}

variable "max_graceful_termination_sec" {
  default = 600
}