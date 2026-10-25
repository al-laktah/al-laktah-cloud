# State is stored in OCI Object Storage, in the bucket created by bootstrap/.
# Locking is automatic: plan/apply write a .lock object next to the state.
#
# Backend blocks can't use variables, so the tenancy-specific settings (bucket,
# namespace, region, profile) live in the git-ignored backend.hcl and are passed in:
#   terraform init -backend-config=backend.hcl
terraform {
  backend "oci" {
    key = "al-laktah-cloud/terraform.tfstate"
  }
}
