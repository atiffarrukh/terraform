provider "azurerm" {
  version = "=2.7"
  features {}
}

provider "azuread" {
  alias = "azure_ad"
  features {}

}