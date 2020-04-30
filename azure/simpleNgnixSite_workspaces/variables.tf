variable "location" {
  default = "eastus2"
}
variable "storage_account_name" {
  type = string
}
variable "vnet_name" {
  type = string
}
variable "vm_name" {
  type = string
}
variable "resource_group_nmae" {
  type = string
}
variable "address_space" {
  type = map(string)
}
variable "subnet_names" {
  type = list(string)
}
variable "instance_count" {
  type = map(number)
}

variable "admin_password" {}

variable "billing_code" {}

variable "subnet_count" {}


locals {
  env_name = lower(terraform.workspace)

  common_tags = {
    BillingCode = var.billing_code
    Environment = terraform.workspace
  }

  storage_account_name = "${var.storage_account_name}-${local.env_name}-${random_integer.rand.result}"
  resource_group_name  = "${var.resource_group_nmae}-${terraform.workspace}"
}