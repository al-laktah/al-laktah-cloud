# Creates the Object Storage bucket that holds the main config's Terraform state.
#
# This is a separate root module on purpose: the bucket has to exist before the
# main config can store its state in it (chicken and egg), and keeping it out of
# the main state means `terraform destroy` up there can never delete its own state.
# This config's own (tiny) state stays local. If it's ever lost, nothing breaks;
# re-adopt the bucket with:
#   terraform import oci_objectstorage_bucket.tfstate n/<namespace>/b/<bucket_name>

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.11"
    }
  }
}

provider "oci" {
  config_file_profile = var.oci_config_profile
  region              = var.region
}

# Every tenancy has one Object Storage namespace, a short random string that is
# part of every bucket's address.
data "oci_objectstorage_namespace" "this" {
  compartment_id = var.tenancy_ocid
}

resource "oci_objectstorage_bucket" "tfstate" {
  compartment_id = var.tenancy_ocid
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = var.bucket_name
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"

  # Keep every previous version of the state file, so a bad apply or an
  # accidental delete can be rolled back.
  versioning = "Enabled"

  freeform_tags = {
    "managed-by" = "terraform"
    "project"    = "al-laktah-cloud"
  }

  # Refuse to delete the bucket that holds your state, even on `terraform destroy`.
  lifecycle {
    prevent_destroy = true
  }
}

# Encrypted restic backups of the services' data (services/backup). It lives here,
# not in the main config, so it outlives the VM: restoring after a rebuild is
# exactly when it's needed. Versioning stays off because restic keeps its own
# history and prunes old data itself; versioning would keep the pruned data forever.
resource "oci_objectstorage_bucket" "backups" {
  compartment_id = var.tenancy_ocid
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = var.backup_bucket_name
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Disabled"

  freeform_tags = {
    "managed-by" = "terraform"
    "project"    = "al-laktah-cloud"
  }

  lifecycle {
    prevent_destroy = true
  }
}
