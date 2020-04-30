##################################################################################
# DATA
##################################################################################


data "template_file" "subnets" {
  count = var.subnet_count

  template = "$${cidrsubnet(vnet_cidr, 8, current_count)}"

  vars = {
    vnet_cidr     = var.address_space[terraform.workspace]
    current_count = count.index
  }
}
##################################################################################
# RESOURCES
##################################################################################
resource "random_integer" "rand" {
  min = 10000
  max = 99999
}

#Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# VNETS
module "vnet" {
  vnet_name           = "${var.vnet_name}-${terraform.workspace}"
  source              = "Azure/vnet/azurerm"
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.address_space[terraform.workspace]]
  subnet_prefixes     = data.template_file.subnets[*].rendered
  subnet_names        = var.subnet_names
  nsg_ids = {
    web      = azurerm_network_security_group.ssh-nsg.id
    database = azurerm_network_security_group.ssh-nsg.id
  }

  tags = local.common_tags
}

# NSG for SSH
resource "azurerm_network_security_group" "ssh-nsg" {
  name                = "ssh-nsg"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-http"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags = local.common_tags
}

# NICs
resource "azurerm_network_interface" "nic" {
  count               = var.instance_count[terraform.workspace]
  name                = "nic-${count.index + 1}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = module.vnet.vnet_subnets[0]
    private_ip_address_allocation = "Dynamic"
  }

  tags = local.common_tags
}

# public IP for load balancer
resource "azurerm_public_ip" "pip" {
  name                = "${var.vm_name}-lb-pip"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"

  tags = local.common_tags

}

#Instances
resource "azurerm_linux_virtual_machine" "linux-machine" {
  count                           = var.instance_count[terraform.workspace]
  name                            = "themachine-${count.index + 1}"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = "Standard_B1s"
  admin_username                  = "atif"
  admin_password                  = var.admin_password
  disable_password_authentication = false
  availability_set_id             = azurerm_availability_set.avset.id
  network_interface_ids = [
    azurerm_network_interface.nic[count.index].id,
  ]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "atif"
      password = var.admin_password
      port     = "5000${count.index + 1}"
      host     = azurerm_public_ip.pip.ip_address
      timeout  = "10m"

      //depends_on = ["azurerm_virtual_machine.vm"]
    }
    inline = [
      "sudo apt update",
      "sudo apt install nginx -y",
      "sudo ufw allow 'Nginx HTTP'",
      "sudo service nginx start",
      "sudo cp /home/atif/nginx /etc/logrotate.d/nginx",
      "sudo logrotate -f /etc/logrotate.conf"
    ]
  }

  tags = local.common_tags
}


# availability set
resource "azurerm_availability_set" "avset" {
  name                         = "${var.vm_name}-avset"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.main.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
  managed                      = true

  tags = local.common_tags
}


# load balancer
resource "azurerm_lb" "load_balancer" {
  name                = "${var.vm_name}-lb"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.pip.id
  }

  tags = local.common_tags
}

# backend pool
resource "azurerm_lb_backend_address_pool" "backend_pool" {
  name                = "BackEndPool"
  resource_group_name = azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer.id
}

# backend pool association
resource "azurerm_network_interface_backend_address_pool_association" "example" {
  count                   = var.instance_count[terraform.workspace]
  backend_address_pool_id = azurerm_lb_backend_address_pool.backend_pool.id
  ip_configuration_name   = "primary"
  network_interface_id    = element(azurerm_network_interface.nic.*.id, count.index)
}

# nat rule
resource "azurerm_lb_nat_rule" "ssh" {
  count                          = var.instance_count[terraform.workspace]
  resource_group_name            = azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.load_balancer.id
  name                           = "SSH-VM-${count.index}"
  protocol                       = "tcp"
  frontend_port                  = "5000${count.index + 1}"
  backend_port                   = 22
  frontend_ip_configuration_name = azurerm_lb.load_balancer.frontend_ip_configuration[0].name
}

# nat rule association
resource "azurerm_network_interface_nat_rule_association" "sshRule" {
  count                 = var.instance_count[terraform.workspace]
  network_interface_id  = element(azurerm_network_interface.nic.*.id, count.index)
  ip_configuration_name = "primary"
  nat_rule_id           = element(azurerm_lb_nat_rule.ssh.*.id, count.index)
}

# azure load balancer rule
resource "azurerm_lb_rule" "lbnatrule" {
  resource_group_name            = azurerm_resource_group.main.name
  loadbalancer_id                = azurerm_lb.load_balancer.id
  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  backend_address_pool_id        = azurerm_lb_backend_address_pool.backend_pool.id
  frontend_ip_configuration_name = "PublicIPAddress"
  probe_id                       = azurerm_lb_probe.example.id
}

# health probe
resource "azurerm_lb_probe" "example" {
  resource_group_name = azurerm_resource_group.main.name
  loadbalancer_id     = azurerm_lb.load_balancer.id
  name                = "http-running-probe"
  port                = 80
}

# storage account
resource "azurerm_storage_account" "example" {
  name                     = "mystra${random_integer.rand.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.common_tags
}

# blob container in storage account
resource "azurerm_storage_container" "site" {
  name                 = "website"
  storage_account_name = azurerm_storage_account.example.name
}

# blob container in storage account
resource "azurerm_storage_container" "state" {
  name                 = "terraform-state"
  storage_account_name = azurerm_storage_account.example.name
}

# upload local html to blob
resource "azurerm_storage_blob" "website" {
  storage_account_name   = azurerm_storage_account.example.name
  name                   = "index.html"
  storage_container_name = azurerm_storage_container.site.name
  type                   = "Block"
  source                 = "index.html"
}

# create sas token for storage account
data "azurerm_storage_account_sas" "sas" {
  connection_string = azurerm_storage_account.example.primary_connection_string
  https_only        = true

  resource_types {
    service   = true
    container = true
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  start  = timestamp()
  expiry = timeadd(timestamp(), "1752h")

  permissions {
    write   = true
    read    = true
    list    = true
    add     = true
    create  = true
    process = false
    update  = false
    delete  = false
  }
}
##################################################################################
# PRIVDERS
##################################################################################
resource "null_resource" "post-config" {
  depends_on = [azurerm_storage_account.example, azurerm_storage_container.site, azurerm_storage_container.state]

  provisioner "local-exec" {
    command = <<EOT
      echo 'storage_account_nmae = "${azurerm_storage_account.example.name}"' >> backend-confi.txt
      echo 'website_container_name = "${azurerm_storage_container.site.name}"' >> backend-confi.txt
      echo 'state_container_name = "${azurerm_storage_container.state.name}"' >> backend-confi.txt
      echo 'key = "terraform.state"' >> backend-confi.txt
      echo 'sas_token = "${data.azurerm_storage_account_sas.sas.sas}"' >> backend-confi.txt
      EOT
  }
}

# resource "null_resource" "copy_files" {
#   depends_on = [azurerm_linux_virtual_machine.linux-machine, azurerm_lb.load_balancer,
#   azurerm_network_interface_nat_rule_association.sshRule]
#   count = var.instance_count[terraform.workspace]
#   provisioner "file" {
#     connection {
#       type     = "ssh"
#       user     = "atif"
#       password = var.admin_password
#       port     = "5000${count.index + 1}"
#       host     = azurerm_public_ip.pip.ip_address
#     }
#     source      = "index.html"
#     destination = "/tmp/index.html"
#   }
#   provisioner "remote-exec" {
#     connection {
#       type     = "ssh"
#       user     = "atif"
#       password = var.admin_password
#       port     = "5000${count.index + 1}"
#       host     = azurerm_public_ip.pip.ip_address
#     }
#     inline =[
#       "mv /tmp/index.html /usr/share/nginx/html",
#       "sleep 10"
#     ]
#   }
# }