# Values derived from variables, so the rest of the config has one place to read them.
locals {
  compartment_id = coalesce(var.compartment_ocid, var.tenancy_ocid)

  common_tags = {
    "managed-by" = "terraform"
    "project"    = "al-laktah-cloud"
  }
}
