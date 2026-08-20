# No default here on purpose - same reasoning as Azure's variables.tf.
# This is Denis's own GCP project ID, specific to his account; a shared
# file that silently defaulted to someone else's project ID would be a
# much worse mistake than being forced to type it in each time.
variable "gcp_project_id" {
  description = "The GCP project this VM gets created in."
  type        = string
}

# Same reasoning as Azure's admin_source_ip: the firewall uses this to
# make sure only this specific machine can SSH in or reach the K3s API.
# Never hardcoded, never defaulted - it changes over time, and shouldn't
# end up committed to a public repository.
variable "admin_source_ip" {
  description = "Denis's own public IP address, as a CIDR block (e.g. 203.0.113.5/32)."
  type        = string
}

# The public half of the same key pair already used for the Azure
# machines could be reused here too, but GCP's own convention ties SSH
# keys to a username directly in the metadata value, so this stays its
# own variable rather than assuming it's identical to Azure's.
variable "admin_ssh_public_key" {
  description = "Denis's SSH public key, in the \"username:ssh-rsa AAAA...\" format GCP's metadata expects."
  type        = string
}
