# A minimal public network: VCN -> internet gateway -> route table -> public subnet.
# The subnet's security list (a stateful firewall) lets almost nothing in: SSH only
# from inside the VCN, since day to day it goes through NetBird. The rest is opened
# per VM, with network security groups (bottom of this file).

resource "oci_core_vcn" "main" {
  compartment_id = local.compartment_id
  display_name   = "main-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "main"
  freeform_tags  = local.common_tags
}

resource "oci_core_internet_gateway" "main" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "main-igw"
  enabled        = true
  freeform_tags  = local.common_tags
}

resource "oci_core_route_table" "public" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "public-rt"
  freeform_tags  = local.common_tags

  # Send all non-local traffic out through the internet gateway.
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "public-sl"
  freeform_tags  = local.common_tags

  # Allow all outbound traffic (package updates, etc.).
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # SSH, by default only from inside the VCN: the Bastion's break-glass sessions
  # (bastion.tf) and the watchtower's check. SSH over NetBird never shows up here: the
  # security list only sees WireGuard's encrypted UDP (the wireguard NSG below).
  # Protocol numbers: 1 = ICMP, 6 = TCP, 17 = UDP.
  ingress_security_rules {
    source      = coalesce(var.ssh_allowed_cidr, var.vcn_cidr)
    protocol    = "6"
    description = "SSH"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # ICMP "fragmentation needed" so Path MTU discovery works.
  ingress_security_rules {
    source      = "0.0.0.0/0"
    protocol    = "1"
    description = "ICMP path MTU discovery"

    icmp_options {
      type = 3
      code = 4
    }
  }

  # ICMP "destination unreachable" from inside the VCN.
  ingress_security_rules {
    source      = var.vcn_cidr
    protocol    = "1"
    description = "ICMP unreachable from VCN"

    icmp_options {
      type = 3
    }
  }
}

resource "oci_core_subnet" "public" {
  compartment_id    = local.compartment_id
  vcn_id            = oci_core_vcn.main.id
  display_name      = "public-subnet"
  cidr_block        = var.public_subnet_cidr
  dns_label         = "public"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.public.id]
  freeform_tags     = local.common_tags

  # Regional subnet (no availability_domain set) so the VM can move ADs freely.
  prohibit_public_ip_on_vnic = false
}

# Network security groups (NSGs) are firewalls attached to individual VMs instead of
# the whole subnet. A VM gets the union of the security list and its NSGs, so each
# one is opened only as far as it needs (netbird.tf has the NetBird VM's own NSG).

# Websites: the main VM (Pocket ID stays public) and the NetBird VM. Port 80 only
# redirects to HTTPS and answers Let's Encrypt's certificate checks.
resource "oci_core_network_security_group" "web" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "web-nsg"
  freeform_tags  = local.common_tags
}

resource "oci_core_network_security_group_security_rule" "web" {
  # One rule per entry; the key becomes the rule's description and its address,
  # e.g. oci_core_network_security_group_security_rule.web["HTTPS"].
  for_each = {
    "HTTP"   = { protocol = "6", port = 80 }
    "HTTPS"  = { protocol = "6", port = 443 }
    "HTTP/3" = { protocol = "17", port = 443 } # HTTPS over UDP
  }

  network_security_group_id = oci_core_network_security_group.web.id
  direction                 = "INGRESS"
  protocol                  = each.value.protocol
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = each.key

  # A dynamic block is written once for each item in its for_each, here once or not
  # at all: TCP rules get tcp_options, UDP rules get udp_options.
  dynamic "tcp_options" {
    for_each = each.value.protocol == "6" ? [each.value.port] : []
    content {
      destination_port_range {
        min = tcp_options.value
        max = tcp_options.value
      }
    }
  }

  dynamic "udp_options" {
    for_each = each.value.protocol == "17" ? [each.value.port] : []
    content {
      destination_port_range {
        min = udp_options.value
        max = udp_options.value
      }
    }
  }
}

# WireGuard, NetBird's tunnel, on every VM. With the port open, a device that can't
# punch through its own NAT (a phone on mobile data) still connects to the VMs
# directly instead of through the relay. WireGuard ignores every packet that isn't
# from a known peer, so the open port gives nothing away.
resource "oci_core_network_security_group" "wireguard" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "wireguard-nsg"
  freeform_tags  = local.common_tags
}

resource "oci_core_network_security_group_security_rule" "wireguard" {
  network_security_group_id = oci_core_network_security_group.wireguard.id
  direction                 = "INGRESS"
  protocol                  = "17" # UDP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  description               = "WireGuard (NetBird)"

  udp_options {
    destination_port_range {
      min = 51820
      max = 51820
    }
  }
}
