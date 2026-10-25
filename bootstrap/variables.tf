variable "tenancy_ocid" {
  description = "OCID of your tenancy (same as tenancy= in ~/.oci/config)."
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.tenancy\\.oc[0-9]+\\.\\.[a-z0-9]{60}$", var.tenancy_ocid))
    error_message = "tenancy_ocid doesn't look like a tenancy OCID (ocid1.tenancy.oc1.. followed by 60 characters). Copy it from tenancy= in ~/.oci/config."
  }
}

variable "region" {
  description = "Region for the bucket, e.g. \"eu-frankfurt-1\". Use your home region; it is also written into backend.hcl."
  type        = string
}

variable "oci_config_profile" {
  description = "Profile name in ~/.oci/config to authenticate with."
  type        = string
  default     = "DEFAULT"
}

variable "bucket_name" {
  description = "Name of the state bucket (unique within your tenancy)."
  type        = string
  default     = "terraform-state"
}

variable "backup_bucket_name" {
  description = "Name of the bucket for service backups. Must match backup_bucket_name in the main config."
  type        = string
  default     = "backups"
}
