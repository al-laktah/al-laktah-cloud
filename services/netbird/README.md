# NetBird

[← All services](../README.md)

The VPN's control server runs on the second Always Free AMD micro VM (`netbird.tf`). [NetBird](https://netbird.io) builds a WireGuard mesh between your devices. This server signs them in, tells them how to reach each other, and relays their traffic only when no direct connection is possible. The stack has four containers:

- **server:** NetBird's combined server: management, signal, relay and STUN in one process. Its config is written in `compose.yaml`, with the secrets filled in from 1Password.
- **dashboard:** the web UI, where you manage devices, users and access policies.
- **caddy:** a Caddy of its own that gets the HTTPS certificate for `netbird.<domain>`. It sends gRPC (HTTP/2 without TLS, `h2c`), the relay and the API to the server, and everything else to the dashboard.
- **backup:** NetBird's nightly backups (see [NetBird's backups](#netbirds-backups)).

Sign-in uses NetBird's built-in identity provider, and Pocket ID can be added as an extra way to sign in. Keep the built-in admin account even then: it still works when the main VM, and with it Pocket ID, is down.

## One-time setup

1. **The VM:** `terraform apply`. Expect 4 to add: the VM, its network security group, the group's STUN rule (UDP 3478) and its DNS record. `netbird_dns_name` must be `netbird.<domain>`.
2. **SSH:** add a `Host netbird` entry to `~/.ssh/config`, a copy of the watchtower's with the new name.
3. **Prepare the VM.** It keeps ports 80/443 open for Caddy, and also opens STUN's port:
   ```sh
   ssh netbird 'sudo OPEN_UDP_PORTS=3478 bash -s' < host/setup-vm.sh
   ```
4. **Secrets, in 1Password.** Never change `store_encryption_key` afterwards: it encrypts parts of the database, so a backup can't be read without the key it was made with.
   ```sh
   op item create --vault=Homelab --category="Secure Note" --title="NetBird" \
     "auth_secret[password]=$(openssl rand -hex 32)" \
     "session_cookie_key[password]=$(openssl rand -base64 32)" \
     "store_encryption_key[password]=$(openssl rand -base64 32)"
   ```
5. **Deploy, then claim the server right away.** Until the first account exists, whoever opens the dashboard first can create it.
   ```sh
   services/deploy.sh netbird
   ```
   Open `https://netbird.<domain>`, create your admin account and save its password in 1Password.
6. **Your first device:** install the [NetBird client](https://docs.netbird.io/get-started/install), then connect it to your server, not NetBird's cloud:
   ```sh
   netbird up --management-url https://netbird.<domain>
   netbird status   # Management: Connected, Signal: Connected
   ```
7. **Optional, sign in with Pocket ID** ([NetBird's guide](https://docs.netbird.io/selfhosted/identity-providers/pocketid)):
   1. In Pocket ID, add an OIDC client called NetBird, with **Public Client** and **PKCE** off. Note its client ID and secret.
   2. Still in Pocket ID, create a user group called NetBird, add yourself to it, and allow that group on the client. Only members can sign in to NetBird through it.
   3. In the NetBird dashboard, go to **Settings → Identity Providers** and add Pocket ID with that client ID and secret, and issuer `https://auth.<domain>` (no trailing slash). Then copy the **Redirect URL** that NetBird shows into the client's **Callback URLs** in Pocket ID. Optionally, add `https://netbird.<domain>/oauth2/logout/callback` under **Logout Callback URLs**.
   4. Sign in with Pocket ID in a private window. The new user waits for approval: approve it under **Team → Users** while signed in as the built-in admin, and make it an Admin. Keep the built-in admin as the owner and backup login.

   A device can only sign in again as the user who added it. To sign in to existing devices with Pocket ID, delete them under **Peers**, then add them again while signed in with Pocket ID.

## Behind NetBird

Only `auth` (Pocket ID), `netbird` itself, shorti's short links and Umami's tracker face the internet. SSH on every VM, the wiki, the start page and creating short links answer only over NetBird (open link shorteners get used to hide phishing, which gets the whole domain blocklisted). The VMs join NetBird as peers, and NetBird's DNS sends your devices to the main VM's NetBird address for the private sites. Do it in this order, so there's always a way in:

1. **The firewalls:** `terraform apply` with `ssh_allowed_cidr = "0.0.0.0/0"` still in `terraform.tfvars`. It creates the Bastion, moves the web ports to network security groups and opens WireGuard's port; SSH stays open. Then test the Bastion once (see [Break-glass access](../../README.md#break-glass-access) in the main README), so you know it works before you need it.
2. **Groups and a setup key**, in the NetBird dashboard:
   - Under **Groups**, create `admins` and `servers`. Add your own devices to `admins`.
   - Under **Setup Keys**, create a key named `servers`: reusable, usage limit 3, expires in 1 day, auto-assigned group `servers`. A VM joined with a setup key never has to sign in again.
3. **Join each VM** and open WireGuard's port in its own firewall (add `3478` on the NetBird VM, and `OPEN_WEB_PORTS=no` on the watchtower):
   ```sh
   ssh <host> 'sudo NETBIRD_URL=https://netbird.<domain> NETBIRD_SETUP_KEY=<key> OPEN_UDP_PORTS=51820 bash -s' < host/setup-vm.sh
   ```
   It ends by printing the VM's NetBird IP and name (`FQDN`).
4. **SSH over NetBird:** in `~/.ssh/config`, point each host at its NetBird name, e.g. `HostName arm-vm-01.netbird.selfhosted`, and check that `ssh <host>` and `services/deploy.sh <stack>` still work.
5. **Access policy:** under **Access Control → Policies**, add `admins` → `servers` (all protocols), then disable the `Default` policy, which lets every peer reach every other. Check SSH again.
6. **The private sites:** under **DNS → Zones**, add one zone per private name, distributed to `admins`: zone `wiki.<domain>` with an A record `wiki.<domain>`, and the same for `shorti.<domain>` and `cloud.<domain>`, all pointing at the main VM's NetBird IP. (shorti is public, but its zone is what lets your devices create links: without it they reach shorti through the public IP, and Caddy refuses.) One zone for the whole `<domain>` would route every name under it (`auth` too) through NetBird's DNS; one zone per name keeps NetBird's DNS out of everything else. Then set `MAIN_VM_PRIVATE_IP` in `config.env` (from `terraform output -raw services_config`) and deploy `edge` and `watchtower`. Check that the wiki loads with NetBird on, and shows *Only available over the VPN* with it off.
7. **Close SSH:** delete the `ssh_allowed_cidr` line from `terraform.tfvars`, then `terraform apply` again. SSH now answers only over NetBird, the Bastion and the VCN.

## Day to day

```sh
ssh netbird 'cd ~/services/netbird && docker compose logs --tail 50 server'
ssh netbird 'docker stats --no-stream'   # memory use on the 1 GB VM
netbird status -d                        # on a device: is each peer P2P (direct) or Relayed?
```

To update NetBird, change the image tags in `compose.yaml` and redeploy. Run a backup first: the server may migrate its database when it starts.

## NetBird's backups

Every night at 02:00 UTC, the stack's `backup` container copies NetBird's three SQLite databases with SQLite's online backup: `store.db` (accounts, devices, policies), `idp.db` (the built-in sign-in) and `events.db` (the activity log). restic then encrypts them, together with any other files in the data folder. The GeoLite location files are left out, because the server downloads them again. Retention is the same as the main VM's: 7 daily, 4 weekly and 6 monthly snapshots.

They go to a bucket of their own, `netbird-backups`. The NetBird VM is the most exposed one, so its policy (`backup.tf`) only lets it write there: if it were ever taken over, the main VM's backups would stay out of its reach. It uses the same restic password (the `Backups` item), so one secret opens both. The [watchtower](../watchtower/README.md) verifies these backups every day as well.

**One-time setup:**

1. **The bucket:** `cd bootstrap && terraform apply`. Expect 1 to add.
2. **The permissions:** `terraform apply` in the repo root. Expect 2 to add (the NetBird VM's dynamic group and policy) and 1 to change (the watchtower's policy can now read the new bucket too).
3. **The setting:** make sure `services/config.env` has `NETBIRD_BACKUP_BUCKET` (it's in `terraform output -raw services_config`).
4. **Deploy, create the restic repository (once, ever), then run a first backup right away:**
   ```sh
   services/deploy.sh netbird
   ssh netbird 'cd ~/services/netbird && docker compose exec backup restic init'
   ssh netbird 'cd ~/services/netbird && docker compose exec backup backup.sh'
   ```
   The backup should end with `no errors were found` and `== backup finished`. If restic says the repository doesn't exist right after `terraform apply`, the new policy isn't active everywhere yet. Wait a few minutes, then try again.
5. **Have the watchtower check it:**
   ```sh
   services/deploy.sh watchtower
   ssh watchtower 'cd ~/services/watchtower && docker compose exec backup-check check.sh netbird'
   ```
   It should end with `== netbird backup check passed: …`.

**Restoring,** on the NetBird VM. The store can only be read with the same `store_encryption_key` that was in use when the backup was made, so never change it in 1Password. After a rebuild, deploy the stack first, so the volume exists:

```sh
cd ~/services/netbird
docker compose run --rm -v ~/restore:/restore backup restic restore latest --target /restore
docker compose stop server
docker compose run --rm -v ~/restore:/r:ro backup sh -c \
  'rm -f /src/netbird/*.db-wal /src/netbird/*.db-shm && cp -a /r/src/netbird/. /src/netbird/ && cp /r/staging/*.db /src/netbird/'
docker compose start server
rm -rf ~/restore   # unencrypted copies
```
