# Every setting this project needs is listed here, in one place, instead of
# being buried inside the resources that use them. If we ever need to change
# a region, a machine size, or an IP address, this is the only file that
# should need editing - main.tf, where the actual resources are defined,
# should not need to change just because a setting changed.

variable "resource_group_name" {
  description = "The name of the folder-like container that will hold every Azure resource this project creates."
  type        = string
  default     = "rg-ha-platform"
}

variable "location_primary" {
  description = "The Azure region for our main, primary cluster: West Europe (Amsterdam)."
  type        = string
  default     = "westeurope"
}

variable "location_secondary" {
  description = "The Azure region for our backup cluster, used when West Europe fails. Originally North Europe (Dublin), but Azure's SKU catalog showed this subscription has capacity restrictions across North Europe for every VM size checked - not specific to one size, the whole region is closed off for this subscription. Germany West Central (Frankfurt) is the replacement: confirmed unrestricted, and it's already where the resource group itself lives."
  type        = string
  default     = "germanywestcentral"
}

variable "vnet_address_space_primary" {
  description = "The private IP address range for the West Europe network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "vnet_address_space_secondary" {
  description = "The private IP address range for the Germany West Central network. Different from West Europe's range on purpose, so the two networks never overlap."
  type        = string
  default     = "10.1.0.0/16"
}

variable "subnet_address_prefix_primary" {
  description = "The smaller address range, inside the West Europe network, where the actual virtual machines will sit."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_address_prefix_secondary" {
  description = "The smaller address range, inside the Germany West Central network, where the actual virtual machines will sit."
  type        = string
  default     = "10.1.1.0/24"
}

variable "admin_source_ip" {
  description = "Denis's own public IP address, written as a CIDR block (for example 203.0.113.5/32). The firewall uses this to make sure only this specific machine can reach the servers for setup and management. There is no default value here on purpose: this is personal to whoever is running the project, it changes over time, and it should never be hardcoded into a file that might end up in a public repository."
  type        = string
}

variable "vm_size" {
  description = "The size (CPU and memory) of every virtual machine in both clusters. Standard_B2s was the original choice - the smallest size that comfortably runs Kubernetes, chosen to keep running cost close to zero - but Azure reported no available capacity for it on this subscription in either West Europe or North Europe. Standard_D2s_v3 is the replacement: not the cheapest possible size, but a mainstream, broadly-available one with no known capacity restrictions, and it comes with more memory (8 GB instead of 4 GB) as a side benefit."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "admin_username" {
  description = "The Linux username created on every virtual machine."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "Denis's SSH public key, used instead of a password to log in to the virtual machines. There is no default value here either, for the same reason as the IP address above: a real key should never be hardcoded into a shared file."
  type        = string
}
