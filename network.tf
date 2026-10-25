# A minimal public network: VCN -> internet gateway -> route table -> public subnet,
# with a security list (stateful firewall) that only lets SSH in.

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

  # SSH from ssh_allowed_cidr (anywhere by default). Protocol numbers: 1 = ICMP, 6 = TCP, 17 = UDP.
  ingress_security_rules {
    source      = var.ssh_allowed_cidr
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
