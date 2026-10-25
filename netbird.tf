# The VPN's control server: NetBird's management, signal, relay and STUN
# (services/netbird), on the second Always Free AMD micro. Devices only talk to it
# to log in and find each other; their traffic flows directly between them when it
# can, and through the relay here only when it can't.

# A network security group (NSG) is a firewall attached to individual VNICs instead
# of a whole subnet. A VNIC gets the union of its subnet's security list and its
# NSGs, so this opens STUN on the NetBird VM only. TCP 80 and 443 come from the
# subnet's security list (network.tf).
resource "oci_core_network_security_group" "netbird" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.netbird_name}-nsg"
  freeform_tags  = local.common_tags
}

# STUN: devices ask it for their public address, so they can connect to each other directly.
resource "oci_core_network_security_group_security_rule" "netbird_stun" {
  network_security_group_id = oci_core_network_security_group.netbird.id
  direction                 = "INGRESS"
  protocol                  = "17" # UDP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "NetBird STUN"

  udp_options {
    destination_port_range {
      min = 3478
      max = 3478
    }
  }
}

resource "oci_core_instance" "netbird" {
  compartment_id      = local.compartment_id
  availability_domain = local.micro_availability_domains[0]
  display_name        = var.netbird_name
  shape               = "VM.Standard.E2.1.Micro"
  freeform_tags       = local.common_tags

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_x86.images[0].id
    boot_volume_size_in_gbs = 50 # counts toward the 200 GB Always Free block storage
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    hostname_label   = var.netbird_name
    nsg_ids          = [oci_core_network_security_group.netbird.id]
  }

  metadata = {
    user_data = local.ssh_user_data
  }

  preserve_boot_volume = false

  lifecycle {
    ignore_changes = [source_details[0].source_id] # same reason as the A1 VM

    precondition {
      condition     = length(local.micro_availability_domains) > 0
      error_message = "No availability domain in this region offers VM.Standard.E2.1.Micro."
    }
  }
}
