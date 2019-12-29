
resource "azurerm_lb" "lb" {
  count                 = var.load_balancer_param == null ? 0 : 1
  name		              = "${local.vm_name}-lb"
  location              = var.location
  resource_group_name   = var.rg

  sku = var.load_balancer_param.sku
    
  frontend_ip_configuration {
    name                          = "lb-frontend-ip"
    subnet_id                     = var.subnet_id
    private_ip_address            = var.subnet_ip_offset == null ? null : cidrhost(var.subnet_prefix, var.subnet_ip_offset)
    private_ip_address_allocation = var.subnet_ip_offset == null ? "dynamic" : "static"
  }
}

resource "azurerm_lb_probe" "probe" {
    resource_group_name       = azurerm_lb.lb.0.resource_group_name
    loadbalancer_id           = azurerm_lb.lb.0.id
    name                      = "${azurerm_lb.lb.0.name}-probe"
    protocol                  = var.load_balancer_param.probe_protocol
    port                      = var.load_balancer_param.probe_port

    interval_in_seconds       = var.load_balancer_param.probe_interval
    number_of_probes          = var.load_balancer_param.probe_num
}

resource "azurerm_lb_backend_address_pool" "lb" {
    resource_group_name             = azurerm_lb.lb.0.resource_group_name
    loadbalancer_id                 = azurerm_lb.lb.0.id
    name                            = "backendpool"

    depends_on    = ["null_resource.dependency_getter"]
}

resource "azurerm_lb_rule" "https" {
    resource_group_name             = azurerm_lb.lb.0.resource_group_name
    loadbalancer_id                 = azurerm_lb.lb.0.id

	  name		                        = "https"
    
    protocol                        = "Tcp"
    frontend_port                   = 443
    backend_port                    = 443

    frontend_ip_configuration_name  = "lb-frontend-ip"
    
	  backend_address_pool_id         = azurerm_lb_backend_address_pool.lb.0.id
    probe_id                        = azurerm_lb_probe.probe.0.id
    depends_on                      = ["azurerm_lb_probe.probe"]

    enable_floating_ip              = true
	  idle_timeout_in_minutes         = 4
	  load_distribution               = "Default"
	  disable_outbound_snat           = false
}

resource "azurerm_lb_rule" "http" {
    resource_group_name             = azurerm_lb.lb.0.resource_group_name
    loadbalancer_id                 = azurerm_lb.lb.0.id

	  name		                        = "http"
 
    protocol                        = "Tcp"
    frontend_port                   = 80
    backend_port                    = 80
    
    frontend_ip_configuration_name  = "lb-frontend-ip"
    
    backend_address_pool_id         = azurerm_lb_backend_address_pool.lb.0.id
    probe_id                        = azurerm_lb_probe.probe.0.id
    depends_on                      = ["azurerm_lb_probe.probe"]

    enable_floating_ip              = true
	  idle_timeout_in_minutes         = 4
	  load_distribution               = "Default"
	  disable_outbound_snat           = false
}

