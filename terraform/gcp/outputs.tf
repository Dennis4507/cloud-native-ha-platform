output "gcp_showcase_public_ip" {
  value       = google_compute_address.static_ip.address
  description = "The static public IP of the GCP showcase VM - used by Ansible, and this is the address the proxy demo is actually reached on."
}
