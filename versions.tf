# Pins the Terraform CLI and provider versions this config is known to work with.
# `~> 9.11` means ">= 9.11, < 10.0": minor/patch upgrades are allowed, the next
# major (which may contain breaking changes) is not.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.11"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.28"
    }
  }
}
