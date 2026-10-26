# A way in that doesn't depend on NetBird: OCI's Bastion service, free on every
# tenancy. If NetBird ever breaks, create a short-lived session in the Console (or
# with the OCI CLI) and SSH to a VM's private IP through it (see README). Nothing
# can connect through the bastion until a session exists, and each session only
# accepts the public key it was created with.
resource "oci_bastion_bastion" "breakglass" {
  bastion_type     = "STANDARD"
  compartment_id   = local.compartment_id
  target_subnet_id = oci_core_subnet.public.id # it reaches the VMs from inside the subnet
  name             = "breakglass"
  freeform_tags    = local.common_tags

  # Sessions are made on demand from wherever you are, so any address may use one.
  client_cidr_block_allow_list = ["0.0.0.0/0"]
  max_session_ttl_in_seconds   = 10800 # 3 hours, the most OCI allows
}
