variable "location" {
  default = "eastus2"
}
variable "vnet_name" {
  type = string
}
variable "vm_name" {
  type = string
}
variable "address_space" {
  default = "10.0.0.0/16"
  type    = string
}
variable "subnet_names" {
  default = ["subnet"]
  type    = list(string)
}
variable "instance_count" {
  default = 1
  type    = number
}

variable "admin_password" {}

variable "billing_code" {}

variable "subnet_count" {}

locals {
  common_tags = {
    BillingCode = var.billing_code
    Environment = terraform.workspace
  }
}