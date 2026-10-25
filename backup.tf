# Lets the VM write its backups (services/backup) to the backups bucket that
# bootstrap/ creates, as itself and with no keys stored on it. OCI gives every
# instance short-lived credentials (an "instance principal"); the dynamic group
# says which instance this is about, and the policy says what it may do.

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.tenancy_ocid
}

resource "oci_identity_dynamic_group" "vm" {
  compartment_id = var.tenancy_ocid # IAM resources always live in the tenancy itself
  name           = var.instance_name
  description    = "The al-laktah-cloud VM, so policies can grant it access as an instance principal"
  matching_rule  = "ALL {instance.id = '${oci_core_instance.arm_vm.id}'}"
  freeform_tags  = local.common_tags
}

resource "oci_identity_policy" "vm_backups" {
  compartment_id = var.tenancy_ocid
  name           = "${var.instance_name}-backups"
  description    = "Lets the al-laktah-cloud VM use its backups bucket, and nothing else"
  freeform_tags  = local.common_tags

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.vm.name} to read buckets in tenancy where target.bucket.name = '${var.backup_bucket_name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.vm.name} to manage objects in tenancy where target.bucket.name = '${var.backup_bucket_name}'",
  ]
}

# The NetBird VM (netbird.tf) writes its own backups to a bucket of their own, and
# may not touch the main VM's.
resource "oci_identity_dynamic_group" "netbird" {
  compartment_id = var.tenancy_ocid
  name           = var.netbird_name
  description    = "The al-laktah-cloud NetBird VM, so policies can grant it access as an instance principal"
  matching_rule  = "ALL {instance.id = '${oci_core_instance.netbird.id}'}"
  freeform_tags  = local.common_tags
}

resource "oci_identity_policy" "netbird_backups" {
  compartment_id = var.tenancy_ocid
  name           = "${var.netbird_name}-backups"
  description    = "Lets the al-laktah-cloud NetBird VM use its own backups bucket, and nothing else"
  freeform_tags  = local.common_tags

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.netbird.name} to read buckets in tenancy where target.bucket.name = '${var.netbird_backup_bucket_name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.netbird.name} to manage objects in tenancy where target.bucket.name = '${var.netbird_backup_bucket_name}'",
  ]
}

# The watchtower (watchtower.tf) verifies the backups independently. It may only
# read them ("read objects" = list and download), so it can't damage what it checks.
resource "oci_identity_dynamic_group" "watchtower" {
  compartment_id = var.tenancy_ocid
  name           = var.watchtower_name
  description    = "The al-laktah-cloud watchtower VM, which checks the backups read-only"
  matching_rule  = "ALL {instance.id = '${oci_core_instance.watchtower.id}'}"
  freeform_tags  = local.common_tags
}

resource "oci_identity_policy" "watchtower_backups" {
  compartment_id = var.tenancy_ocid
  name           = "${var.watchtower_name}-backups"
  description    = "Lets the al-laktah-cloud watchtower read the backups buckets, and nothing else"
  freeform_tags  = local.common_tags

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.watchtower.name} to read buckets in tenancy where target.bucket.name = '${var.backup_bucket_name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.watchtower.name} to read objects in tenancy where target.bucket.name = '${var.backup_bucket_name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.watchtower.name} to read buckets in tenancy where target.bucket.name = '${var.netbird_backup_bucket_name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.watchtower.name} to read objects in tenancy where target.bucket.name = '${var.netbird_backup_bucket_name}'",
  ]
}
