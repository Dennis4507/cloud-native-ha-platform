# Terraform keeps a running record of everything it has created, called
# "state". This file tells Terraform where that record should live: inside
# an Azure Storage account, rather than as a plain file on this laptop.
# Storing it remotely means the record survives even if this machine is
# wiped, and it can eventually be shared safely with a teammate.
#
# The block below is left empty on purpose. It only says "the state lives
# in Azure Storage" - it does not say which storage account, because that
# name is unique to this specific Azure subscription and gets generated
# by scripts/bootstrap-tfstate.sh. Those specific details are supplied
# separately, when we first run "terraform init", from a small file called
# backend-config.hcl that is never committed to Git. This way, anyone who
# copies this project starts from the same clean template, without
# accidentally inheriting a storage account that only exists in this
# Azure subscription.
terraform {
  backend "azurerm" {}
}
