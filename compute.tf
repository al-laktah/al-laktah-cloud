# Data sources READ existing information from OCI; they never create anything.

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Newest Ubuntu 24.04 image built for the A1 (aarch64) shape.
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = local.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  # Exclude the "Minimal" variant.
  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-24\\.04-aarch64-"]
    regex  = true
  }
}

# The Always Free AMD micro shape (1/8 OCPU, 1 GB RAM, x86), used by the watchtower
# and NetBird VMs. A region may offer it in only one availability domain, so the
# domain is looked up, not picked by index.
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

# Newest x86 Ubuntu 24.04 image for the micro VMs (the A1 VM's images are Arm and won't boot there).
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

resource "oci_core_instance" "arm_vm" {
  compartment_id      = local.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
  display_name        = var.instance_name
  shape               = "VM.Standard.A1.Flex"
  freeform_tags       = local.common_tags

  # Flex shapes let you choose the CPU/memory split.
  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    hostname_label   = var.instance_name
    # Firewalls for this VM only (network.tf). Changing them updates the VM in place.
    nsg_ids = [oci_core_network_security_group.web.id, oci_core_network_security_group.wireguard.id]
  }

  # cloud-init installs the SSH keys on first boot (see local.ssh_user_data in main.tf)
  metadata = {
    user_data = local.ssh_user_data
  }

  # Delete the boot volume with the instance so `terraform destroy` leaves nothing behind.
  preserve_boot_volume = false

  lifecycle {
    # Oracle publishes new images regularly. Without this, every new image would make
    # Terraform want to destroy and recreate the VM. Rebuild deliberately with:
    #   terraform apply -replace=oci_core_instance.arm_vm
    ignore_changes = [source_details[0].source_id]
  }
}
