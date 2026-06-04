output "resource_group_name" {
  value       = azurerm_resource_group.sre-networking-rg.name
}

output "vnet_name" {
  value       = azurerm_virtual_network.sre-vnet1.name
}

output "subnet_system_id" {
  value       = azurerm_subnet.sre-subnet-system.id
}

output "subnet_user_id" {
  value       = azurerm_subnet.sre-subnet-user.id
}

