output "instance_public_ip" {
  description = "Public IP of the VM."
  value       = oci_core_instance.arm_vm.public_ip
}

output "hostname" {
  description = "DNS name pointing at the VM."
  value       = cloudflare_dns_record.vm.name
}

output "ssh_command" {
  description = "Ready-to-paste SSH command."
  value       = "ssh ubuntu@${cloudflare_dns_record.vm.name}"
}

output "availability_domain" {
  description = "Availability domain the VM landed in."
  value       = oci_core_instance.arm_vm.availability_domain
}

output "watchtower_public_ip" {
  description = "Public IP of the watchtower VM."
  value       = oci_core_instance.watchtower.public_ip
}

output "watchtower_hostname" {
  description = "DNS name pointing at the watchtower VM."
  value       = cloudflare_dns_record.watchtower.name
}

output "netbird_public_ip" {
  description = "Public IP of the NetBird VM."
  value       = oci_core_instance.netbird.public_ip
}

output "netbird_hostname" {
  description = "DNS name pointing at the NetBird VM."
  value       = cloudflare_dns_record.netbird.name
}

output "backup_config" {
  description = "Settings for services/config.env, used by the backup stack."
  value       = <<-EOT
    OCI_NAMESPACE=${data.oci_objectstorage_namespace.this.namespace}
    OCI_REGION=${oci_core_instance.arm_vm.region}
    OCI_COMPARTMENT_OCID=${var.tenancy_ocid}
    BACKUP_BUCKET=${var.backup_bucket_name}
  EOT
}

output "image_name" {
  description = "Image the VM was built from (at the time of first apply)."
  value       = data.oci_core_images.ubuntu_arm.images[0].display_name
}
