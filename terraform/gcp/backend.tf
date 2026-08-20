# Same remote state backend already set up for the Azure side - one
# storage account can hold state for multiple, entirely unrelated
# Terraform projects, as long as each uses its own "key" (the blob's own
# filename within that storage account). Nothing GCP-specific needed here;
# reusing the exact same backend-config.hcl Azure already uses, just with
# a different key set at init time.
terraform {
  backend "azurerm" {}
}
