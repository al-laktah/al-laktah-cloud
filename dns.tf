# An A record that follows the VM's public IP. Because `content` references the instance, Terraform creates this after the VM, and updates it in the same apply if the VM is ever rebuilt and gets a new ephemeral IP.

resource "cloudflare_dns_record" "vm" {
  zone_id = var.cloudflare_zone_id
  name    = var.dns_name
  type    = "A"
  content = oci_core_instance.arm_vm.public_ip
  ttl     = 1 # 1 = "Automatic" (300s for DNS-only records)
  comment = "Managed by Terraform (al-laktah-cloud)"

  # DNS only ("grey cloud"). Cloudflare's proxy only carries HTTP/HTTPS, so SSH through a proxied record would hit Cloudflare instead of the VM.
  proxied = false
}

# One A record per website served from the VM, following its public IP the same way.

resource "cloudflare_dns_record" "services" {
  for_each = toset(var.service_dns_names)

  zone_id = var.cloudflare_zone_id
  name    = each.value
  type    = "A"
  content = oci_core_instance.arm_vm.public_ip
  ttl     = 1
  comment = "Managed by Terraform (al-laktah-cloud)"

  # DNS only as well, the VM gets its own HTTPS certificates.
  proxied = false
}
