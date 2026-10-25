# ---------------------------------------------------------------------------
# Account / authentication
# ---------------------------------------------------------------------------

variable "tenancy_ocid" {
  description = "OCID of your tenancy (Profile menu -> Tenancy). Used to look up availability domains."
  type        = string

  # A mistyped OCID doesn't error: OCI just returns empty lists, which fail later
  # with confusing "index null value" errors. Catch it up front instead.
  validation {
    condition     = can(regex("^ocid1\\.tenancy\\.oc[0-9]+\\.\\.[a-z0-9]{60}$", var.tenancy_ocid))
    error_message = "tenancy_ocid doesn't look like a tenancy OCID (ocid1.tenancy.oc1.. followed by 60 characters). Copy it from tenancy= in ~/.oci/config."
  }
}

variable "compartment_ocid" {
  description = "Compartment to create resources in. Leave null to use the tenancy's root compartment."
  type        = string
  default     = null
}

variable "oci_config_profile" {
  description = "Profile name in ~/.oci/config to authenticate with."
  type        = string
  default     = "DEFAULT"
}

variable "region" {
  description = "OCI region, e.g. \"eu-frankfurt-1\". Must be your HOME region for Always Free compute. Null uses the region from ~/.oci/config."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vcn_cidr" {
  description = "Address range for the virtual cloud network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Address range for the public subnet (must sit inside vcn_cidr)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "ssh_allowed_cidr" {
  description = "Source range allowed to SSH in. Open to the internet by default; access is controlled by ssh_public_keys."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid CIDR block, e.g. \"203.0.113.7/32\"."
  }
}

# ---------------------------------------------------------------------------
# DNS (Cloudflare)
# ---------------------------------------------------------------------------

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID of the domain (dashboard -> domain -> Overview -> API section). Not secret."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.cloudflare_zone_id))
    error_message = "cloudflare_zone_id must be the 32-character hex zone ID."
  }
}

variable "dns_name" {
  description = "Fully qualified hostname to point at the VM, e.g. \"cloud.example.com\"."
  type        = string
}

variable "service_dns_names" {
  description = "Hostnames of the websites served from the VM, each gets its own A record, e.g. [\"shorti.example.com\"]."
  type        = list(string)
  default     = []

  # A URL instead of a bare hostname would otherwise only fail at the Cloudflare API.
  validation {
    condition     = alltrue([for name in var.service_dns_names : can(regex("^([a-z0-9-]+\\.)+[a-z]{2,}$", name))])
    error_message = "service_dns_names must be bare hostnames such as \"shorti.example.com\", without https:// or a path."
  }
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "instance_name" {
  description = "Display name and hostname for the VM."
  type        = string
  default     = "arm-vm-01"
}

variable "availability_domain_index" {
  description = "Which availability domain to use (0-based). Bump this if you hit \"Out of host capacity\"."
  type        = number
  default     = 0
}

# The validations below stop you from asking for more than the Always Free
# allowance (2 OCPUs / 12 GB for A1, 200 GB block storage) by accident.
variable "instance_ocpus" {
  description = "Ampere A1 OCPUs for the VM. Always Free allows 2 in total."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_ocpus >= 1 && var.instance_ocpus <= 2
    error_message = "Always Free covers at most 2 A1 OCPUs."
  }
}

variable "instance_memory_gbs" {
  description = "Memory in GB for the VM. Always Free allows 12 GB in total."
  type        = number
  default     = 12

  validation {
    condition     = var.instance_memory_gbs >= 1 && var.instance_memory_gbs <= 12
    error_message = "Always Free covers at most 12 GB of A1 memory."
  }
}

variable "boot_volume_size_gbs" {
  description = "Boot volume size in GB. Always Free gives 200 GB of block storage in total (boot + block volumes)."
  type        = number
  default     = 50

  validation {
    condition     = var.boot_volume_size_gbs >= 50 && var.boot_volume_size_gbs <= 200
    error_message = "Boot volume must be between 50 and 200 GB."
  }
}

variable "ssh_public_keys" {
  description = "SSH public keys authorised for the \"ubuntu\" user, one key per string. Security-key (sk-*) keys are supported."
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0
    error_message = "Provide at least one SSH public key, or you will be locked out of the VM."
  }
}
