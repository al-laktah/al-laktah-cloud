# The OCI provider authenticates with an API signing key described in
# ~/.oci/config (see README). Nothing secret lives in this repo.
provider "oci" {
  config_file_profile = var.oci_config_profile

  # null means "use the region from the profile in ~/.oci/config".
  region = var.region
}

# Reads its API token from the CLOUDFLARE_API_TOKEN environment variable, which
# `op run --env-file=terraform.env` sets for each command (see README), so the token
# never appears in code, tfvars or state.
provider "cloudflare" {}
