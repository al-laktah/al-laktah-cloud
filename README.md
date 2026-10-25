# al-laktah-cloud

Oracle Cloud **Always Free** infrastructure, managed with Terraform.

Current contents: one Ampere A1 (Arm) VM, **2 OCPUs / 12 GB RAM / 50 GB boot volume**, running Ubuntu 24.04 in its own public network. SSH is open to the internet, and only the keys in `ssh_public_keys` (`variables.tf`) can log in. A Cloudflare A record, `cloud.al-laktah.com`, follows the VM's public IP. That uses the whole Always Free A1 allowance (2 OCPUs, 12 GB) and 50 of the 200 GB of free block storage.

## Files

| File | What it does |
| --- | --- |
| `versions.tf` | Pins the Terraform and OCI provider versions |
| `providers.tf` | Configures the OCI provider (auth from `~/.oci/config`) and the Cloudflare provider (auth from `CLOUDFLARE_API_TOKEN`) |
| `variables.tf` | Inputs, with validation that keeps you inside the free limits |
| `main.tf` | `locals`: shared derived values such as the compartment and tags |
| `network.tf` | VCN, internet gateway, route table, security list, subnet |
| `compute.tf` | Image lookup and the VM itself |
| `dns.tf` | Cloudflare A record pointing at the VM (DNS only, not proxied) |
| `outputs.tf` | Values printed after `apply` (IP, SSH command) |
| `terraform.tfvars.example` | Template for your personal values |

## One-time setup

### 1. Install Terraform

```sh
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version
```

(Plain `brew install terraform` is frozen at 1.5.7 because of the licence change, so use HashiCorp's tap.)

### 2. Create an OCI API key

Terraform signs its API calls to OCI with a key pair.

1. In the OCI Console, open the profile menu (top right), then **My profile**, then **API keys** (it may be listed as **Tokens and keys**), then **Add API key**.
2. Choose **Generate API key pair**, download the **private key** and click **Add**.
3. Move the key into place and lock down its permissions:
   ```sh
   mkdir -p ~/.oci
   mv ~/Downloads/<downloaded-key>.pem ~/.oci/oci_api_key.pem
   chmod 600 ~/.oci/oci_api_key.pem
   ```
4. The Console shows a **Configuration file preview**. Paste it into `~/.oci/config` and set `key_file`:
   ```ini
   [DEFAULT]
   user=ocid1.user.oc1..aaaa...
   fingerprint=aa:bb:cc:...
   tenancy=ocid1.tenancy.oc1..aaaa...
   region=eu-frankfurt-1
   key_file=~/.oci/oci_api_key.pem
   ```
   `region` must be your **home region**: Always Free compute can only be created there.

### 3. Create a Cloudflare API token

1. In the Cloudflare dashboard, open **My Profile**, then **API Tokens**, then **Create Token**, and use the **Edit zone DNS** template.
2. Under **Zone Resources**, choose **Include → Specific zone → al-laktah.com**, then create the token.
3. Save the token in 1Password, e.g. as an API Credential item named `Cloudflare Terraform` in the Personal vault. Don't put it in any file in this repo.

### 4. Fill in your variables

```sh
cp terraform.tfvars.example terraform.tfvars
```

Fill in `tenancy_ocid` (the same value as `tenancy=` in `~/.oci/config`) and `cloudflare_zone_id` (the domain's **Overview** page, **API** section). `terraform.tfvars` is git-ignored.

Check the SSH keys in `ssh_public_keys` (`variables.tf`) **before the first apply**: they are baked into the VM when it is created (see Gotchas).

## The Terraform workflow

Load the Cloudflare token into your shell first (once per terminal session):

```sh
export CLOUDFLARE_API_TOKEN=$(op read "op://Personal/Cloudflare Terraform/credential")
```

`op://` references only allow letters, digits, `-`, `_`, `.` and spaces in vault, item and field names. If a name has anything else (e.g. parentheses), rename the item or use its ID instead (`op item list` shows IDs).

```sh
terraform init        # download the OCI provider and create .terraform.lock.hcl (commit the lock file)
terraform fmt         # format the code
terraform validate    # check syntax and types; no API calls
terraform plan        # show what WOULD change; changes nothing
terraform apply       # make the changes (asks for confirmation)
terraform output      # print outputs again later
terraform destroy     # delete everything this config created
```

After `apply`, connect with:

```sh
$(terraform output -raw ssh_command)
```

If your private key isn't one SSH tries by default (for example the YubiKey handle `~/.ssh/blk-yubikey-ssh`), add `-i <private key>`, or add a host entry to `~/.ssh/config`:

```
Host oci-arm
  HostName cloud.al-laktah.com
  User ubuntu
  IdentityFile ~/.ssh/blk-yubikey-ssh
```

Some useful commands for learning:

```sh
terraform state list                                # every resource Terraform is tracking
terraform state show oci_core_instance.arm_vm       # everything Terraform knows about the VM
terraform console                                   # try expressions, e.g. local.compartment_id
terraform apply -replace=oci_core_instance.arm_vm   # rebuild the VM on purpose (e.g. new image)
```

## Gotchas

- **"Out of host capacity"** means there is no free A1 capacity in that availability domain right now. Set `availability_domain_index = 1` (or `2`, if your region has 3 ADs), or retry later. Upgrading the account to Pay As You Go usually fixes this, and resources within the Always Free limits remain free.
- **SSH keys are fixed at launch.** They reach the VM through cloud-init `user_data` (OCI's own `ssh_authorized_keys` field rejects YubiKey `sk-` keys), and OCI rejects changes to `user_data` after an instance starts. To add or remove a key later, edit `~/.ssh/authorized_keys` on the VM, or update `ssh_public_keys` and rebuild with `-replace`.
- **SSH is open to the whole internet**, so expect constant bot login attempts in the logs. They fail because the image allows key-only logins. To narrow access later, set `ssh_allowed_cidr`, or put the VM behind Tailscale or the OCI Bastion service.
- **Idle reclamation.** Oracle may reclaim an Always Free VM if, over 7 days, its 95th-percentile CPU, network *and* memory utilisation are all under 20%.
- **Opening more ports later** (e.g. 80/443) takes two changes: a security list rule in `network.tf` *and* the VM's own firewall. Oracle's Ubuntu images ship with restrictive `iptables` rules that allow only SSH.
- **State is local** (`terraform.tfstate`, git-ignored). It is Terraform's record of what it created. Don't delete it, or Terraform loses track of your resources. A good next step is moving it to OCI Object Storage.
- **The image is chosen once.** `compute.tf` ignores newer Ubuntu images after the first apply, so they don't trigger a rebuild. Use `-replace` when you want one.

## Ideas for next steps

- Remote state in an Object Storage bucket (free: 20 GB)
- A reserved public IP, so the address survives a rebuild
- `cloud-init` user data to install packages on first boot
- A separate block volume for data
- Refactor the network and VM into reusable modules
