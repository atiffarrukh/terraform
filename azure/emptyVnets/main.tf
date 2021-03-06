#############################################################################
# VARIABLES
#############################################################################

variable "resource_group_name" {
    type = string
}

variable "location" {
    type = string
    default = "eastus2"
}

variable "vnet_cidr_range" {
    type = list(string)
    default = ["10.0.0.0/16"]
}

variable "subnet_prefixes" {
    type = list(string)
    default = ["10.0.1.0/24","10.0.2.0/24"]
}

variable "subnet_names" {
    type = list(string)
    default = ["web","database"]
}

#############################################################################
# PROVIDERS
#############################################################################
provider "azurerm" {
    features{}
}

#############################################################################
# RESOURCES
#############################################################################

resource "azurerm_resource_group" "rg" {
    location = var.location
    name = var.resource_group_name
}

module "vnet-main" {
  source              = "Azure/vnet/azurerm"
  resource_group_name = azurerm_resource_group.rg.name
  vnet_name           = var.resource_group_name
  address_space       = var.vnet_cidr_range
  subnet_prefixes     = var.subnet_prefixes
  subnet_names        = var.subnet_names
  nsg_ids             = {}

  tags = {
    environment = "dev"
    costcenter  = "it"

  }
}

#############################################################################
# OUTPUTS
#############################################################################

output "vnet_id" {
    value = module.vnet-main.vnet_id
}