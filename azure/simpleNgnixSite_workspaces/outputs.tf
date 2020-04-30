output "lb_dns" {
  value = azurerm_public_ip.pip.ip_address
}

output "storage_account_nmae" {
  value = azurerm_storage_account.example.name
}

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}