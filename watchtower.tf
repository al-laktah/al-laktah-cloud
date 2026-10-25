# A small, separate VM that watches the main one: Gatus checks the sites, and an
# independent job verifies the backups (services/watchtower). It runs on the
# Always Free AMD micro shape (1/8 OCPU, 1 GB RAM, x86), which a region may offer
# in only one availability domain, so the domain is looked up, not picked by index.

data "oci_core_shapes" "micro" {
  for_each            = toset([for ad in data.oci_identity_availability_domains.ads.availability_domains : ad.name])
  compartment_id      = local.compartment_id
  availability_domain = each.value

  filter {
    name   = "name"
    values = ["VM.Standard.E2.1.Micro"]
  }
}

locals {
  micro_availability_domains = [for ad, result in data.oci_core_shapes.micro : ad if length(result.shapes) > 0]
}

# Newest x86 Ubuntu 24.04 image (the A1 VM's images are Arm and won't boot here).
data "oci_core_images" "ubuntu_x86" {
  compartment_id           = local.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-24\\.04-[0-9]"]
    regex  = true
  }
}

resource "oci_core_instance" "watchtower" {
  compartment_id      = local.compartment_id
  availability_domain = local.micro_availability_domains[0]
  display_name        = var.watchtower_name
  shape               = "VM.Standard.E2.1.Micro" # fixed size, so no shape_config
  freeform_tags       = local.common_tags

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_x86.images[0].id
    boot_volume_size_in_gbs = 50 # counts toward the 200 GB Always Free block storage
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    hostname_label   = var.watchtower_name
  }

  metadata = {
    user_data = local.ssh_user_data
  }

  preserve_boot_volume = false

  lifecycle {
    ignore_changes = [source_details[0].source_id] # same reason as the A1 VM

    # Fails with a clear message instead of an "index out of range" error.
    precondition {
      condition     = length(local.micro_availability_domains) > 0
      error_message = "No availability domain in this region offers VM.Standard.E2.1.Micro."
    }
  }
}
