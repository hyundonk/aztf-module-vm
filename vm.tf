locals {
  merged_instances = merge(var.instances_defaults, var.instances) 
  prefix								= local.merged_instances.prefix

  vm_name 							= local.prefix == null ? local.merged_instances.name : "${local.prefix}-${local.merged_instances.name}"
  vm_size								= local.merged_instances.vm_size
  vm_num								= local.merged_instances.vm_num
  subnet_ip_offset			= local.merged_instances.subnet_ip_offset
  vm_publisher					= local.merged_instances.vm_publisher
  vm_offer							= local.merged_instances.vm_offer
  vm_sku								= local.merged_instances.vm_sku
  vm_version						= local.merged_instances.vm_version
  postfix								= local.merged_instances.postfix
  storageAccountName    = var.diag_storage_account_name == null ? null : element(split("/", var.diag_storage_account_name), 8)

  enable_accelerated_networking = local.merged_instances.vm_size == "Standard_D2s_v3" ? "false" : "true"
}

resource "azurerm_availability_set" "avset" {
  count                         = local.vm_num == 1 ? 0 : 1 # create only if multiple instances cases

  name                  	      = "${local.vm_name}-avset"
  location              	      = var.location
  resource_group_name  	        = var.resource_group_name
	
  platform_update_domain_count  = var.update_domain_count
  platform_fault_domain_count   = var.fault_domain_count

  managed                       = true
	
  proximity_placement_group_id	= var.enable_proximity_place_group == true ? azurerm_proximity_placement_group.ppg.0.id : null
}

resource "azurerm_proximity_placement_group" "ppg" {
  count                         = var.enable_proximity_place_group == true ? 1 : 0 # create only if multiple instances cases

  name                          = "${local.vm_name}-ppg"
  location                      = var.location
  resource_group_name           = var.resource_group_name
}

resource "azurerm_network_interface" "nic" {
  count 					                      = local.vm_num
  name                                  = local.vm_num == 1 ? "${local.vm_name}-nic" : format("%s%03d-nic", local.vm_name, count.index + 1)

  location            	                = var.location
  resource_group_name  	                = var.resource_group_name
	
  ip_configuration {
    name 															= "ipconfig0"
    subnet_id 												= var.subnet_id
    private_ip_address_allocation     = local.subnet_ip_offset == null ? "dynamic" : "static"
    
    # if subnet_ip_offset is not set, use dynamic ip address. If load balancer is used, reserve the first ip to load balancer and assign the next ip address(es) to vm(s)
    private_ip_address                = local.subnet_ip_offset == null ? null : var.load_balancer_param == null? cidrhost(var.subnet_prefix, local.subnet_ip_offset + count.index) : (var.load_balancer_ip != null ? cidrhost(var.subnet_prefix, local.subnet_ip_offset + count.index): cidrhost(var.subnet_prefix, local.subnet_ip_offset + 1 + count.index))
    public_ip_address_id              = var.public_ip_id     == null ? null : var.public_ip_id
  }
  
    enable_accelerated_networking       	= local.enable_accelerated_networking
}

resource "azurerm_network_interface" "nic2" {
  count 					                      = var.add_second_nic == false ? 0 : local.vm_num
  name                                  = local.vm_num == 1 ? "${local.vm_name}-nic2" : format("%s%03d-nic2", local.vm_name, count.index + 1)

  location            	                = var.location
  resource_group_name  	                = var.resource_group_name
	
  ip_configuration {
    name 															= "ipconfig0"
    subnet_id 												= var.subnet_id_second_nic
    private_ip_address_allocation     = "dynamic"
    
    private_ip_address                = cidrhost(var.subnet_prefix_second_nic, local.subnet_ip_offset + count.index)
    public_ip_address_id              = var.public_ip_id_second_nic == null ? null : var.public_ip_id_second_nic[count.index]
  }
  
  enable_accelerated_networking       	= local.enable_accelerated_networking
}

resource "azurerm_virtual_machine" "vm" {
  lifecycle {
    ignore_changes = [ # don't recreate existing disk
      storage_os_disk
		]
  }

  count					                        = local.vm_num
  name                                  = local.vm_num == 1 ? local.vm_name: local.postfix == null ? format("%s%03d", local.vm_name, count.index + 1) : format("%s%03d%s", local.vm_name, count.index + 1, local.postfix) 

  location        	   	                = var.location
  resource_group_name 	                = var.resource_group_name
  vm_size               	              = local.vm_size

  delete_os_disk_on_termination 				= true
  delete_data_disks_on_termination 			= true

  availability_set_id                   = local.vm_num == 1 ? null : azurerm_availability_set.avset.0.id

  proximity_placement_group_id              = var.enable_proximity_place_group == true ? azurerm_proximity_placement_group.ppg.0.id : null

  storage_image_reference {
    id                    = var.image_id
    publisher             = var.image_id != null ? null : local.vm_publisher
    offer                 = var.image_id != null ? null : local.vm_offer
    sku                   = var.image_id != null ? null : local.vm_sku
    version               = var.image_id != null ? null : local.vm_version
  }
  
  dynamic "plan" {
    for_each = var.plan == null ? [] : ["plan"]
    content {
      name        	      = var.plan.name
      product             = var.plan.product
      publisher           = var.plan.publisher
    }
  }

  storage_os_disk {
    name          = local.vm_num == 1 ? "${local.vm_name}-osdisk" : local.postfix == null ? format("%s%03d-osdisk", local.vm_name, count.index + 1) : format("%s%03d%s-osdisk", local.vm_name, count.index + 1, local.postfix) 

    caching       		    = "ReadWrite"
    create_option 		    = "FromImage"
    managed_disk_type 	  = var.os_disk_type # "Premium_LRS"
    disk_size_gb          = var.os_disk_size
  }

  identity { # added to enable 'Azure Monitor Sink' feature
    type = "SystemAssigned"
  }

  os_profile {
    computer_name          = local.vm_num == 1 ? local.vm_name: local.postfix == null ? format("%s%03d", local.vm_name, count.index + 1) : format("%s%03d%s", local.vm_name, count.index + 1, local.postfix) 
    admin_username        = var.admin_username
    admin_password        = var.admin_password
    custom_data           = var.custom_data == null ? null : var.custom_data
    #custom_data           = var.custom_data == null ? null : filebase64(var.custom_data)
  }
/*  
  dynamic "storage_data_disk" {
    for_each = var.data_disk == null ? [] : ["DataDisk"]
    content {
      name        	      = var.data_disk.name
      managed_disk_id     = var.data_disk.id
      create_option       = "Attach"
      lun                 = 0
      disk_size_gb        = var.data_disk.size
    }
  }
*/ 
  dynamic "storage_data_disk" {
    for_each = var.data_disk
    content {
      name                = local.vm_num == 1 ? format("%s-datadisk-%02d", local.vm_name, storage_data_disk.key) : local.postfix == null ? format("%s%03d-datadisk-%02d", local.vm_name, count.index + 1, storage_data_disk.key) : format("%s%03d%s-datadisk-%02d", local.vm_name, count.index + 1, local.postfix, storage_data_disk.key) 
      managed_disk_type   = storage_data_disk.value.type # "Premium_LRS"
      create_option       = "Empty"
      lun                 = storage_data_disk.key
      disk_size_gb        = storage_data_disk.value.disk_size
    }
  }
 
  dynamic "os_profile_windows_config" {
    for_each = local.vm_offer == "WindowsServer" ? ["WindowsServer"] : []
    content {
      provision_vm_agent    = true
    }
  }

  dynamic "os_profile_linux_config" {
    for_each = local.vm_offer == "WindowsServer" ? [] : var.ssh_key_data != null ? [1] : []
    content {
      disable_password_authentication = true
      ssh_keys {
        key_data  = var.ssh_key_data
        path      = var.ssh_key_path
      }
    }

  }
	
  dynamic "os_profile_linux_config" {
    for_each = local.vm_offer == "WindowsServer" ? [] : var.ssh_key_data != null ? [] : [1]
    content {
      disable_password_authentication = false
    }
  }

  dynamic "boot_diagnostics" {
    for_each = var.boot_diagnostics_endpoint == null ? [] : ["BootDiagnostics"]
    content {
      enabled               = var.boot_diagnostics_endpoint != null ? true : false
      storage_uri           = var.boot_diagnostics_endpoint
    }
  }

  network_interface_ids  = var.subnet_id_second_nic == null  ? [element(azurerm_network_interface.nic.*.id, count.index)] : [element(azurerm_network_interface.nic.*.id, count.index), element(azurerm_network_interface.nic2.*.id, count.index)]
  #network_interface_ids   = [element(concat(azurerm_network_interface.nic.*.id, list("")), count.index)]

  primary_network_interface_id = var.subnet_id_second_nic == null ? null : element(azurerm_network_interface.nic.*.id, count.index)

  tags = var.tags
}

resource "azurerm_network_interface_backend_address_pool_association" "association" {
  count = var.load_balancer_param == null ? 0 : local.vm_num

  network_interface_id      = element(azurerm_network_interface.nic.*.id, count.index)
  ip_configuration_name     = "ipconfig0"
  backend_address_pool_id   = azurerm_lb_backend_address_pool.lb.0.id
}

resource "azurerm_network_interface_backend_address_pool_association" "association_outbound" {
	count                     = var.backend_outbound_address_pool_id == null ? 0 : local.vm_num

	network_interface_id      = element(azurerm_network_interface.nic.*.id, count.index)
	ip_configuration_name     = "ipconfig0"
	backend_address_pool_id   = var.backend_outbound_address_pool_id
}


resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "association" {
	count                     = var.backend_address_pool_id == null ? 0 : local.vm_num
	
	network_interface_id      = element(azurerm_network_interface.nic.*.id, count.index)
	ip_configuration_name     = "ipconfig0"
	backend_address_pool_id   = var.backend_address_pool_id
}

# Refer https://docs.microsoft.com/en-us/azure/azure-monitor/platform/diagnostics-extension-schema-windows
resource "azurerm_virtual_machine_extension" "diagnostics" {
	count                         = var.diag_storage_account_name == null ? 0 : local.vm_offer == "WindowsServer" ? local.vm_num : 0
	
	name                          = "Microsoft.Insights.VMDiagnosticsSettings"
	#location              	      = var.location
	#resource_group_name  	        = var.resource_group_name

	virtual_machine_id						= element(azurerm_virtual_machine.vm.*.id, count.index)
	#virtual_machine_name   	      = element(azurerm_virtual_machine.vm.*.name, count.index)

	publisher            	        = "Microsoft.Azure.Diagnostics"
	type                 	        = "IaaSDiagnostics"
	type_handler_version 	        = "1.5"

	auto_upgrade_minor_version    = true

	settings = <<SETTINGS
	{
		"xmlCfg"            :  "${base64encode(templatefile("${path.module}/wadcfgxml.tmpl", { resource_id = element(azurerm_virtual_machine.vm.*.id, count.index)}))}",
    "storageAccount"    : "${local.storageAccountName}"
	}
	SETTINGS
	protected_settings = <<SETTINGS
	{
    "storageAccountName": "${local.storageAccountName}",
		"storageAccountKey" : "${var.diag_storage_account_access_key}",
		"storageAccountEndpoint" : "${var.diag_storage_account_endpoint}"
	}
	SETTINGS
}

# https://docs.microsoft.com/ko-kr/azure/virtual-machines/extensions/oms-windows 
# https://docs.microsoft.com/ko-kr/azure/virtual-machines/extensions/oms-linux
resource "azurerm_virtual_machine_extension" "monioring" {
	count 						            = var.log_analytics_workspace_id == null ? 0 : local.vm_num
	
	name 						              = "OMSExtension" 
	#location 					            = var.location
	#resource_group_name  	        = var.resource_group_name
	virtual_machine_id						= element(azurerm_virtual_machine.vm.*.id, count.index)
	#virtual_machine_name   		    = element(azurerm_virtual_machine.vm.*.name, count.index)

	publisher 					          = "Microsoft.EnterpriseCloud.Monitoring"
	type 						              = local.vm_offer == "WindowsServer" ? "MicrosoftMonitoringAgent" : "OmsAgentForLinux"
	type_handler_version 		      = local.vm_offer == "WindowsServer" ? "1.0" : "1.7"
	auto_upgrade_minor_version 	  = true

	settings = <<SETTINGS
	{
		"workspaceId"               : "${var.log_analytics_workspace_id}"
	}
	SETTINGS
	protected_settings = <<PROTECTED_SETTINGS
	{
		"workspaceKey"              : "${var.log_analytics_workspace_key}"
	}
	PROTECTED_SETTINGS
}

resource "azurerm_virtual_machine_extension" "network_watcher" {
	count 						            = var.enable_network_watcher_extension == true ? local.vm_num : 0
	
	name 						              = "Microsoft.Azure.NetworkWatcher" 
	#location 					            = var.location
	#resource_group_name  	        = var.resource_group_name
	virtual_machine_id						= element(azurerm_virtual_machine.vm.*.id, count.index)
	#virtual_machine_name   		    = element(azurerm_virtual_machine.vm.*.name, count.index)
	
	publisher 					          = "Microsoft.Azure.NetworkWatcher"
	type 						              = local.vm_offer == "WindowsServer" ? "NetworkWatcherAgentWindows" : "NetworkWatcherAgentLinux"
	type_handler_version 		      = "1.4"
	auto_upgrade_minor_version 	  = true
}

resource "azurerm_virtual_machine_extension" "dependency_agent" {
	count 						            = var.enable_dependency_agent == true ? local.vm_num : 0
	
	name 						              = "DependencyAgentWindows" 
	#location 					            = var.location
	#resource_group_name  	        = var.resource_group_name
	virtual_machine_id						= element(azurerm_virtual_machine.vm.*.id, count.index)
	#virtual_machine_name   		    = element(azurerm_virtual_machine.vm.*.name, count.index)
	
	publisher 					          = "Microsoft.Azure.Monitoring.DependencyAgent"
	type 						              = local.vm_offer == "WindowsServer" ? "DependencyAgentWindows" : "DependencyAgentLinux"
	type_handler_version 		      = "9.5"
	auto_upgrade_minor_version 	  = true
}

resource "azurerm_virtual_machine_extension" "aadlogin" {
	  count 						            = var.enable_aadlogin == true ? local.vm_num : 0
    name                          = "ext-aadlogin-${count.index}"
	  virtual_machine_id						= element(azurerm_virtual_machine.vm.*.id, count.index)
    
    publisher                     = "Microsoft.Azure.ActiveDirectory"
    type                          = "AADLoginForWindows"
    type_handler_version          = "0.3"
    auto_upgrade_minor_version    = true
}

/*
resource "azurerm_virtual_machine_extension" "iis" {
	count					                = var.custom_script_path == "" ? 0 : local.vm_num
	
	name 						              = "CustomScriptExtension"
	#location 					            = var.location
	#resource_group_name  	        = var.resource_group_name
	virtual_machine_id						= element(azurerm_virtual_machine.vm.*.id, count.index)
	#virtual_machine_name   		    = element(azurerm_virtual_machine.vm.*.name, count.index)
	
	publisher 					          = "Microsoft.Compute"
	type 						              = "CustomScriptExtension"
	type_handler_version 		      = "1.8"
	auto_upgrade_minor_version 	  = true

	settings = <<SETTINGS
  {
    "fileUris"                  : [
			"https://ebaykrtfbackend.blob.core.windows.net/scripts/install_iis.ps1"
		],
		"commandToExecute"          : "powershell -ExecutionPolicy Unrestricted -File \"install_iis.ps1\""
  }
	SETTINGS
}


resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "association2" {
	count                     = var.backend_address_pool_id2 == null ? 0 : local.vm_num
	
	network_interface_id      = element(azurerm_network_interface.nic.*.id, count.index)
	ip_configuration_name     = "ipconfig0"
	backend_address_pool_id   = var.backend_address_pool_id2
}

output "vm_map" {
	value = azurerm_virtual_machine.vm
}
*/
