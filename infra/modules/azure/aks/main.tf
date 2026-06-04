data "azurerm_virtual_network" "existing" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_kubernetes_cluster" "sre_cluster" {
  name                = var.cluster_name
  location            = var.region
  resource_group_name = var.resource_group_name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.cluster_version
  sku_tier            = var.sku_tier

  node_resource_group = "${var.resource_group_name}-nodes"

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name       = "system"
    vm_size    = var.vm_size

    vnet_subnet_id = var.subnet_system_id

    type    = "VirtualMachineScaleSets"
    # mode    = "System"

    enable_auto_scaling = true 

    node_count = var.node_count
    min_count  = 1
    max_count  = 10

    os_disk_type = "Managed"
  }

  storage_profile {
    blob_driver_enabled = true
    disk_driver_enabled = true  
    snapshot_controller_enabled = true
  }


  auto_scaler_profile {
    max_graceful_termination_sec = var.max_graceful_termination_sec
    skip_nodes_with_local_storage = true
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"

    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }

  tags = {
    Environment = "Production"
    Project     = "SRE-PROJECT"
  }
}


resource "azurerm_kubernetes_cluster_node_pool" "user_pool" {
  name                  = "userpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.sre_cluster.id

  vm_size    = var.vm_size
  node_count = 1

  vnet_subnet_id = var.subnet_user_id

  enable_auto_scaling = true
  min_count           = 1 
  max_count           = 5

  node_labels = {
    workload = "general"
    env      = "prod"
    team     = "platform"
  } 

  node_taints = [
    "workload=general:NoSchedule"
  ]
}