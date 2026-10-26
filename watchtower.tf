# A small, separate VM that watches the main one: Gatus checks the sites, and an
# independent job verifies the backups (services/watchtower). It runs on the
# Always Free AMD micro shape; the shape and image lookups are in compute.tf.

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
    nsg_ids          = [oci_core_network_security_group.wireguard.id] # serves nothing publicly
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
