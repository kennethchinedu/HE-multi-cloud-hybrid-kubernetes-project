resource "azurerm_resource_group" "sre-networking-rg" {
  name     = var.resource_group_name
  location = var.region
}

resource "azurerm_virtual_network" "sre-vnet1" {
  name = var.vnet_name
  location = var.region
  resource_group_name = azurerm_resource_group.sre-networking-rg.name
  address_space = var.vnet_cidr
}   

resource "azurerm_subnet" "sre-subnet-system" {
  name = "sre-subnet1"
  resource_group_name = azurerm_resource_group.sre-networking-rg.name
  virtual_network_name = azurerm_virtual_network.sre-vnet1.name
  address_prefixes = var.aks_subnet_system
}

resource "azurerm_subnet" "sre-subnet-user" {
  name = "sre-subnet2"
  resource_group_name = azurerm_resource_group.sre-networking-rg.name
  virtual_network_name = azurerm_virtual_network.sre-vnet1.name
  address_prefixes = var.aks_subnet_user
}

resource "azurerm_network_security_group" "sre-nsg" { 
  name = "sre-nsg"
  location = var.region
  resource_group_name = azurerm_resource_group.sre-networking-rg.name
  security_rule {
    name = "allow-ssh"
    priority = 100
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "22"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name = "allow-http"
    priority = 101
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "80"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name = "allow-https"
    priority = 102
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "443"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "sre-subnet-system-nsg-association" {
  subnet_id = azurerm_subnet.sre-subnet-system.id
  network_security_group_id = azurerm_network_security_group.sre-nsg.id
}

resource "azurerm_subnet_network_security_group_association" "sre-subnet-user-nsg-association" {
  subnet_id = azurerm_subnet.sre-subnet-user.id
  network_security_group_id = azurerm_network_security_group.sre-nsg.id
}