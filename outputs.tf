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

output "image_name" {
  description = "Image the VM was built from (at the time of first apply)."
  value       = data.oci_core_images.ubuntu_arm.images[0].display_name
}
