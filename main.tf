# Values derived from variables, so the rest of the config has one place to read them.
locals {
  compartment_id = coalesce(var.compartment_ocid, var.tenancy_ocid)

  common_tags = {
    "managed-by" = "terraform"
    "project"    = "al-laktah-cloud"
  }

  # SSH keys are handed to cloud-init (which runs on a VM's first boot) as user_data
  # rather than OCI's own ssh_authorized_keys field, because the OCI API rejects
  # security-key types such as YubiKey's "sk-ssh-ed25519@openssh.com". cloud-init
  # installs them for the "ubuntu" user. OCI won't change user_data after launch; see README.
  ssh_user_data = base64encode(join("\n", [
    "#cloud-config",
    yamlencode({ ssh_authorized_keys = var.ssh_public_keys }),
  ]))
}
