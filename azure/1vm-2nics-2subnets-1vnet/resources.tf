data "template_file" "subnets" {
  count = var.subnet_count

  template = "$${cidrsubnet(vnet_cidr, 8, current_count)}"

  vars = {
    vnet_cidr     = var.address_space
    current_count = count.index
  }
}

resource "azurerm_resource_group" "main" {
  name     = "main-rg"
  location = var.location
  tags     = local.common_tags
}

# VNETS
module "vnet" {
  vnet_name           = "${var.vnet_name}-${terraform.workspace}"
  source              = "Azure/vnet/azurerm"
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.address_space]
  subnet_prefixes     = data.template_file.subnets[*].rendered
  subnet_names        = var.subnet_names
  nsg_ids = {
    subnet = azurerm_network_security_group.rdp-nsg.id
  }

  tags = local.common_tags
}

resource "azurerm_network_security_group" "rdp-nsg" {
  name     = "rdp-nsg"
  location = var.location
  resource_group_name = azurerm_resource_group.main.name
  security_rule {
    name                       = "allow-rdp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# NICs
resource "azurerm_network_interface" "nic" {
  count               = 2
  name                = "nic-${count.index + 1}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "nic-config-${count.index}"
    subnet_id                     = module.vnet.vnet_subnets[0]
    private_ip_address_allocation = "Dynamic"
  }

  tags = local.common_tags
}

resource "azurerm_windows_virtual_machine" "example" {
  name                = "example-machine"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_F2"
  admin_username      = "atiffarrukh"
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.nic.0.id,
    azurerm_network_interface.nic.1.id

  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
}