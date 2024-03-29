
resource "azurerm_lb" "lb" {
  count                 = var.load_balancer_param == null ? 0 : 1
  name		              = "${local.vm_name}-lb"
  location              = var.location
	resource_group_name  	= var.resource_group_name

  sku = var.load_balancer_param.sku
    
  frontend_ip_configuration {
    name                          = "lb-frontend-ip"
    public_ip_address_id          = var.load_balancer_pip_id

    subnet_id                     = var.load_balancer_pip_id == null ? var.subnet_id : null
    private_ip_address            = var.load_balancer_pip_id == null ? (var.load_balancer_ip == null ? (local.subnet_ip_offset == null ? null : cidrhost(var.subnet_prefix, local.subnet_ip_offset)) : var.load_balancer_ip) : null
    private_ip_address_allocation = var.load_balancer_pip_id == null ? (local.subnet_ip_offset == null ? "dynamic" : "static") : null

#    gateway_load_balancer_frontend_ip_configuration_id = var.gateway_load_balancer_id
  }
  tags = var.tags
}

resource "azurerm_lb_probe" "probe" {
  count                 = var.load_balancer_param == null ? 0 : 1

  resource_group_name   = azurerm_lb.lb.0.resource_group_name
  loadbalancer_id       = azurerm_lb.lb.0.id
  name                  = "${azurerm_lb.lb.0.name}-probe"
  protocol              = var.load_balancer_param.probe_protocol
  port                  = var.load_balancer_param.probe_port

  interval_in_seconds   = var.load_balancer_param.probe_interval
  number_of_probes      = var.load_balancer_param.probe_num
}

resource "azurerm_lb_backend_address_pool" "lb" {
  count                 = var.load_balancer_param == null ? 0 : 1
  loadbalancer_id       = azurerm_lb.lb.0.id
  name                  = "backendpool"
  resource_group_name   = azurerm_lb.lb.0.resource_group_name
/*
  dynamic "tunnel_interface" {
    for_each = var.load_balancer_param.sku == "Gateway" ? ["Gateway"] : []
    content {
      identifier  = 800
      type        = "Internal"
      protocol    = "VXLAN"
      port        = 2000
    }
  }

  dynamic "tunnel_interface" {
    for_each = var.load_balancer_param.sku == "Gateway" ? ["Gateway"] : []
    content {
      identifier  = 801
      type        = "External"
      protocol    = "VXLAN"
      port        = 2001
    }
  }
*/
}

resource "azurerm_lb_rule" "ha" {
  count                           = var.load_balancer_param == null ? 0 : (var.load_balancer_param.sku == "Gateway" ? 0 : 1)

  resource_group_name             = azurerm_lb.lb.0.resource_group_name
  loadbalancer_id                 = azurerm_lb.lb.0.id

	name		                        = "ha"

  protocol                        = "All"
  frontend_port                   = 0
  backend_port                    = 0
 
  frontend_ip_configuration_name  = "lb-frontend-ip"
   
	backend_address_pool_id         = azurerm_lb_backend_address_pool.lb.0.id
  #backend_address_pool_ids        = [azurerm_lb_backend_address_pool.lb.0.id]
  
  probe_id                        = azurerm_lb_probe.probe.0.id
  depends_on                      = [azurerm_lb_probe.probe]

  enable_floating_ip              = false # must be false when used for internal load balancing
	idle_timeout_in_minutes         = 4
}


resource "azurerm_lb_rule" "https" {
  count                           = var.load_balancer_param == null ? 0 : (var.load_balancer_param.sku == "Gateway" ? 0 : 1)

  resource_group_name             = azurerm_lb.lb.0.resource_group_name
  loadbalancer_id                 = azurerm_lb.lb.0.id

	name		                        = "https"
    
  protocol                        = "Tcp"
  frontend_port                   = 443
  backend_port                    = 443

  frontend_ip_configuration_name  = "lb-frontend-ip"
   
	backend_address_pool_id         = azurerm_lb_backend_address_pool.lb.0.id
  #backend_address_pool_ids        = [azurerm_lb_backend_address_pool.lb.0.id]
  probe_id                        = azurerm_lb_probe.probe.0.id
  depends_on                      = [azurerm_lb_probe.probe]

  enable_floating_ip              = false # must be false when used for internal load balancing
	idle_timeout_in_minutes         = 4
	load_distribution               = "Default"
	disable_outbound_snat           = false
}

resource "azurerm_lb_rule" "http" {
  count                           = var.load_balancer_param == null ? 0 : (var.load_balancer_param.sku == "Gateway" ? 0 : 1)
  
  resource_group_name             = azurerm_lb.lb.0.resource_group_name
  loadbalancer_id                 = azurerm_lb.lb.0.id

	name		                        = "http"
 
  protocol                        = "Tcp"
  frontend_port                   = 80
  backend_port                    = 80
    
  frontend_ip_configuration_name  = "lb-frontend-ip"
    
  backend_address_pool_id         = azurerm_lb_backend_address_pool.lb.0.id
  #backend_address_pool_ids         = [azurerm_lb_backend_address_pool.lb.0.id]

  probe_id                        = azurerm_lb_probe.probe.0.id
  depends_on                      = [azurerm_lb_probe.probe]

  enable_floating_ip              = false # must be false when used for internal load balancing
	idle_timeout_in_minutes         = 4
	load_distribution               = "Default"
	disable_outbound_snat           = false
}

