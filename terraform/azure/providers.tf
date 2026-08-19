# This file tells Terraform two things: which version of Terraform this
# project expects, and which "provider" it needs installed to talk to
# Azure. A provider is a plugin - without it, Terraform has no idea how to
# create an Azure resource group or a virtual machine; it only knows the
# generic language, not the Azure-specific vocabulary.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # "~> 3.100" means: any version starting with 3.100 is fine, including
      # small updates and bug fixes, but do not jump to version 4.x on your
      # own. Azure's provider changed some default behaviour in version 4,
      # and that kind of change should be a decision we make on purpose,
      # not something that happens quietly during a routine update.
      version = "~> 3.100"
    }
  }
}

# This block switches the Azure provider on.
provider "azurerm" {
  features {}

  # Notice there is no username, password, or key anywhere in this file.
  # Terraform authenticates using whichever account is currently logged in
  # through the Azure command line ("az login") on this machine, or through
  # environment variables when running in an automated pipeline. This means
  # nobody could accidentally leak a credential by committing this file to
  # a public repository - there simply isn't one written down here.

  # By default, Terraform tries to automatically switch on every single
  # Azure service it knows how to manage - dozens of them, most of which
  # this project never touches (databases, IoT, machine learning...). That
  # only works for an identity with broad, subscription-wide rights, which
  # the sandbox identity deliberately does not have. Turning this off means
  # only the handful of services this platform actually uses get switched
  # on, explicitly, by the root account, once - a more precise and
  # auditable approach than silently enabling everything by default.
  skip_provider_registration = true
}
