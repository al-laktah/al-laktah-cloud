output "namespace" {
  description = "Object Storage namespace of the tenancy."
  value       = data.oci_objectstorage_namespace.this.namespace
}

output "bucket_name" {
  description = "Name of the state bucket."
  value       = oci_objectstorage_bucket.tfstate.name
}

output "backup_bucket_name" {
  description = "Name of the backups bucket."
  value       = oci_objectstorage_bucket.backups.name
}

output "netbird_backup_bucket_name" {
  description = "Name of the NetBird VM's backups bucket."
  value       = oci_objectstorage_bucket.netbird_backups.name
}

# Ready-made partial backend configuration for the main config:
#   terraform output -raw backend_config > ../backend.hcl
output "backend_config" {
  description = "Contents for ../backend.hcl."
  value       = <<-EOT
    bucket              = "${oci_objectstorage_bucket.tfstate.name}"
    namespace           = "${data.oci_objectstorage_namespace.this.namespace}"
    region              = "${var.region}"
    config_file_profile = "${var.oci_config_profile}"
  EOT
}
