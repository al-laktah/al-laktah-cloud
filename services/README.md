# Services

Docker Compose stacks that run on the VMs. The main VM's stacks all sit behind one Caddy edge proxy.

| Stack | URL | What it is |
| --- | --- | --- |
| `edge/` | | Caddy edge proxy, and the only container on the main VM that publishes ports (80, 443, 443/udp). Gets HTTPS certificates for every site in `edge/config/sites/` automatically |
| `pocket-id/` | `auth.<domain>` | [Pocket ID](https://pocket-id.org): a passkey-only OpenID Connect provider that signs you in to the other services |
| `outline/` | `wiki.<domain>` | [Outline](https://www.getoutline.com) wiki, with its Postgres and Redis |
| `homepage/` | `cloud.<domain>` | [Homepage](https://gethomepage.dev): the start page listing the services, with sign-in through Pocket ID. Its configuration is the YAML in `homepage/config/` |
| `backup/` | | Nightly encrypted [restic](https://restic.net) backups of every service's data to OCI Object Storage (see [Backups](#backups)) |
| `watchtower/` | | Runs on the separate watchtower VM. [Gatus](https://github.com/TwiN/gatus) monitors the sites and certificates, and a daily job verifies the backups read-only (see [Watchtower](#watchtower)) |
| `netbird/` | `netbird.<domain>` | Runs on the separate NetBird VM. The [NetBird](https://netbird.io) VPN server and dashboard, behind a Caddy of its own (see [NetBird](#netbird)) |

[shorti](https://github.com/al-laktah/shorti) also runs on the VM, but it is built and deployed from its own repo (see below). This repo only provides its DNS record and its site file in `edge/config/sites/`.

## How it fits together

- **DNS:** Terraform creates an A record for each hostname in `service_dns_names` (`terraform.tfvars`).
- **Routing:** the edge proxy terminates TLS and forwards each hostname to a container by name, over a shared external Docker network called `web`. Databases and caches stay on their own stack's private network.
- **VPN-only sites:** a site file that starts with `import vpn_only` answers only NetBird addresses (and the VCN, for the watchtower); everyone else gets a 403. `auth` stays public, because you sign in to NetBird with it. See [Behind NetBird](#behind-netbird).
- **Secrets:** they live in 1Password. Each stack commits an `.env.tpl` that contains only `op://` references. `deploy.sh` fills them in with `op inject` and writes the result straight to `.env` on the VM.
- **On the VM:** each stack lives in `~/services/<service>`, and its data is in named Docker volumes (`docker volume ls`).

## Prerequisites

- The VM is prepared with [`host/setup-vm.sh`](../host/setup-vm.sh). It installs updates (with automatic reboots for security fixes), opens ports 80/443 in the VM's own firewall, installs Docker with the Compose plugin (the `ubuntu` user joins the `docker` group), turns on log rotation and creates the `web` network. Run it once on a new VM, from your laptop: `ssh <host> 'sudo bash -s' < host/setup-vm.sh`. Running it again is safe.
- The 1Password CLI (`op`), signed in on your laptop.
- `services/config.env`: run `cp services/config.env.example services/config.env`, then fill in `DEPLOY_HOST`, `DEPLOY_SSH_KEY` and `DOMAIN`. `DEPLOY_SSH_KEY` is the key that `deploy.sh` offers, and the only one. It can be a private key file, a YubiKey handle, or the `.pub` file of a key held by an agent such as 1Password.

## Deploying

```sh
services/deploy.sh <service>   # e.g. services/deploy.sh outline
```

The script syncs the stack to `~/services/<service>`, writes its `.env` and runs `docker compose up -d`. Running it again is safe, so redeploy after every change. Deploying `edge` also reloads Caddy's config, so new sites go live without a restart. It refuses to sync into a folder that is a git checkout, so apps deployed from their own repo, like shorti, are never overwritten.

## First-time setup: Pocket ID and Outline

1. **DNS.** Make sure `auth.<domain>` and `wiki.<domain>` are in `service_dns_names`, then `terraform apply`. Caddy can only get a certificate once the name resolves.
2. **Secrets.** Create them in 1Password. The values are generated on the spot and never shown:
   ```sh
   op item create --vault=Private --category="Secure Note" --title="Pocket ID" \
     "encryption_key[password]=$(openssl rand -base64 32)"
   op item create --vault=Private --category="Secure Note" --title="Outline" \
     "secret_key[password]=$(openssl rand -hex 32)" \
     "utils_secret[password]=$(openssl rand -hex 32)" \
     "postgres_password[password]=$(openssl rand -hex 24)"
   ```
3. **The edge proxy and Pocket ID.**
   ```sh
   services/deploy.sh edge
   services/deploy.sh pocket-id
   ```
   Open `https://auth.<domain>/setup`, create your admin account and add your YubiKey as a passkey. Add a **second passkey** too (e.g. one stored in 1Password), so losing the YubiKey doesn't lock you out.
4. **The Outline OIDC client.** In Pocket ID, go to **OIDC Clients → Add**. Name it `Outline`, set the callback URL to `https://wiki.<domain>/auth/oidc.callback`, and the logout callback URL to exactly `https://wiki.<domain>` (no trailing slash). Without that, signing out leaves you on Pocket ID's own logout page instead of back at Outline, which in the desktop app looks like nothing happened. The client secret is shown **only once**, so store it right away:
   ```sh
   op item edit Outline --vault=Private \
     "oidc_client_id[text]=<client id>" "oidc_client_secret[password]=<client secret>"
   ```
5. **Outline.**
   ```sh
   services/deploy.sh outline
   ```
   Open `https://wiki.<domain>` and choose **Continue with Pocket ID**. The first person to sign in creates the workspace and becomes its admin. Only users that exist in Pocket ID can sign in, and Pocket ID has no public sign-up.

Lost every passkey? On the VM, run `cd ~/services/pocket-id && docker compose exec pocket-id /app/pocket-id one-time-access-token <username>`. It prints a one-hour sign-in link; use it to add a new passkey.

## Adding a service

1. Add its hostname to `service_dns_names`, then `terraform apply`.
2. Create `services/<name>/compose.yaml`:
   - Join the external `web` network, and don't publish any `ports:`.
   - Read secrets as `${VAR:?}`, with matching `op://` references in `services/<name>/.env.tpl`.
   - Keep data in named volumes. `deploy.sh` syncs with `--delete`, so a bind mount inside `~/services/<name>` would be wiped on the next deploy.
3. Create `services/edge/config/sites/<name>.caddy`. Leave out `import vpn_only` only for a site that must be public:
   ```
   <subdomain>.{$DOMAIN} {
   	import vpn_only
   	reverse_proxy <container name on the web network>:<container port>
   }
   ```
4. For a VPN-only site, add a NetBird DNS zone for its name (see [Behind NetBird](#behind-netbird)), and its name to the gatus container's `extra_hosts` in `watchtower/compose.yaml`.
5. Add a tile to `homepage/config/services.yaml`, with a `siteMonitor` at the container's address on the `web` network.
6. Run `services/deploy.sh <name>`, then deploy `edge`, `homepage` and `watchtower`.

CI checks every folder that has a `compose.yaml` with `docker compose config`, using placeholder values for the `op://` references.

## Homepage

The start page at `cloud.<domain>`: one tile per service, each with a status dot, plus the main VM's CPU, memory and disk. It's VPN-only like the wiki, and asks you to sign in with Pocket ID.

The **Gatus** tile shows how many checks are up and down, read from Gatus on the watchtower across the VCN (`WATCHTOWER_PRIVATE_IP` in `config.env`; the watchtower's firewall lets only the main VM in). Clicking it opens the Gatus dashboard over NetBird.

Everything on the page comes from the YAML in `homepage/config/`: `services.yaml` for the tiles, `widgets.yaml` for the top row, `bookmarks.yaml` for the links, `settings.yaml` for the layout. Edit and redeploy; `deploy.sh`'s fingerprint restarts Homepage when a file changes. Write `{{HOMEPAGE_VAR_DOMAIN}}` instead of your domain, so the files stay generic.

**One-time setup:**

1. **Pocket ID:** add an OIDC client called Homepage, with callback URL `https://cloud.<domain>/api/auth/callback/homepage-oidc`. Homepage lets in anyone Pocket ID accepts, so allow only your own user group on the client.
2. **Secrets, in 1Password**, with the client's ID and secret from step 1:
   ```sh
   op item create --vault=Private --category="Secure Note" --title="Homepage" \
     "auth_secret[password]=$(openssl rand -base64 32)" \
     "oidc_client_id[text]=<client ID>" \
     "oidc_client_secret[password]=<client secret>"
   ```
3. **VPN-only DNS:** in NetBird, add the zone `cloud.<domain>` with an A record `cloud.<domain>` pointing at the main VM's NetBird IP, distributed to `admins` (see [Behind NetBird](#behind-netbird)). `cloud.<domain>` is the VM's own public record (`dns_name`), so its certificate renews as usual.
4. **Deploy:** `services/deploy.sh homepage`, then `services/deploy.sh edge` for the new site, and `services/deploy.sh watchtower` for its check.

## Apps with their own repo (shorti)

shorti builds its images from source, so it is deployed from a checkout of its repo on the VM, not by `deploy.sh`:

```sh
ssh <host> 'cd ~/services/shorti && git pull && docker compose up -d --build'
```

Its frontend joins the `web` network as `shorti`, and `edge/config/sites/shorti.caddy` routes `shorti.<domain>` to it. To bring it under `deploy.sh` later, have the shorti repo's CI publish Arm images to a registry (e.g. GHCR). Then a `services/shorti/compose.yaml` here can use `image:` instead of `build:`.

## Updating a service

Bump the image tag in its `compose.yaml` and deploy. Outline runs database migrations automatically when it starts, so take a backup first (see below).

## Backups

Every night at 02:30 UTC, the `backup` stack:
1. Dumps Outline's Postgres database.
2. Copies Pocket ID's and shorti's SQLite databases with SQLite's online backup, which stays consistent while the apps keep writing.
3. Sends those copies, plus Outline's uploaded files and Pocket ID's uploads, to restic.

restic encrypts everything on the VM, uploads only what changed, and keeps **7 daily, 4 weekly and 6 monthly** snapshots. It then checks the repository.

The backups go to the `backups` bucket that `bootstrap/` creates. Because that bucket isn't part of the main config, it survives even a full rebuild of the VM. The VM signs in to OCI as itself (an *instance principal*: see `backup.tf`), and a policy limits it to that one bucket. So the VM holds no cloud credentials. **The only secret is the restic password: without it, the backups can't be decrypted.**

### One-time setup

1. **The bucket:** `cd bootstrap && terraform apply`. Expect 1 to add.
2. **The VM's permission:** `terraform apply` in the repo root. Expect 2 to add: the dynamic group and the policy. Policies can take a minute to take effect.
3. **The restic password, in 1Password:**
   ```sh
   op item create --vault=Private --category="Secure Note" --title="Backups" \
     "restic_password[password]=$(openssl rand -base64 32)"
   ```
4. **The settings:** copy the output of `terraform output -raw services_config` into `services/config.env`.
5. **Deploy, create the restic repository (once, ever), then run a first backup right away:**
   ```sh
   services/deploy.sh backup
   ssh <host> 'cd ~/services/backup && docker compose exec backup restic init'
   ssh <host> 'cd ~/services/backup && docker compose exec backup backup.sh'
   ```
   The backup should end with `no errors were found` and `== backup finished`. The nightly run never creates the repository itself. A failed read looks just like a missing repository, and initialising over an existing one would lock you out of every backup already in it.

   If restic says the repository doesn't exist right after `terraform apply`, a new policy can take a few minutes to apply everywhere. Wait, then try again.

### Day to day

```sh
cd ~/services/backup                                    # on the VM
docker compose logs --tail 50 backup                    # last night's run
docker compose exec backup backup.sh                    # run a backup now
docker compose exec backup restic snapshots             # list snapshots
docker compose exec backup restic dump latest /staging/outline.sql | head   # peek into the latest one
```

Nobody reads those logs every day. To get an email when a night's backup fails or doesn't run, create a free check at [healthchecks.io](https://healthchecks.io) and put its ping URL in `BACKUP_PING_URL` in `services/config.env`. Then redeploy `backup`.

### Restoring

On the VM, first restore the latest snapshot into `~/restore` (use `restic snapshots` and a snapshot ID instead of `latest` for an older one):

```sh
cd ~/services/backup
docker compose run --rm -v ~/restore:/restore backup restic restore latest --target /restore
```

`~/restore/staging/` then holds the database copies and `~/restore/src/` the files. Restore only what you need, stopping each app first:

- **Outline database:**
  ```sh
  cd ~/services/outline && docker compose stop outline
  docker compose exec -T postgres psql -q -U outline -d outline < ~/restore/staging/outline.sql
  docker compose start outline
  ```
- **Outline files:**
  ```sh
  docker run --rm --entrypoint cp -v outline_files:/data -v ~/restore/src/outline-files:/from:ro services/backup:local -a /from/. /data/
  ```
- **Pocket ID** (users, passkeys, OIDC clients):
  ```sh
  cd ~/services/pocket-id && docker compose stop pocket-id
  docker run --rm --entrypoint sh -v pocket-id_data:/data -v ~/restore:/r:ro services/backup:local -c \
    'rm -f /data/pocket-id.db-wal /data/pocket-id.db-shm && cp /r/staging/pocket-id.db /data/pocket-id.db && cp -a /r/src/pocket-id/. /data/ && chown -R 1000:1000 /data'
  docker compose start pocket-id
  ```
- **shorti:**
  ```sh
  cd ~/services/shorti && docker compose stop api
  docker run --rm --entrypoint sh -v shorti_shorti-data:/data -v ~/restore:/r:ro services/backup:local -c \
    'rm -f /data/andy.db-wal /data/andy.db-shm && cat /r/staging/shorti.db > /data/andy.db'
  docker compose start api
  ```

**After a VM rebuild,** deploy the stacks first, so their volumes exist. Then restore as above. Rebuilding gives the VM a new OCID; `terraform apply` updates the dynamic group to match it.

Delete `~/restore` when you're done; it holds unencrypted copies of everything.

## Watchtower

A separate, Always Free AMD micro VM (`watchtower.tf`) watches the main VM from outside, because a VM that hangs can't report on itself. It runs two containers (`services/watchtower/`):

- **Gatus** checks `wiki`, `cloud`, `auth`, `shorti` and `netbird` over HTTPS and the main VM's SSH port, every minute. The VPN-only sites and SSH are checked across the VCN, at the main VM's private IP (`MAIN_VM_PRIVATE_IP`). It sends an alert to your phone through [ntfy](https://ntfy.sh) after 3 failed checks in a row, or when a certificate has less than 10 days left. It sends another when things recover.
- **backup-check** verifies the backups of both VMs every day at 06:00 UTC, first the main VM's, then the NetBird VM's:
  1. The latest backup is less than 26 hours old.
  2. The repository passes `restic check`, which also downloads and verifies a different quarter of all backup data each day (all of it every 4 days).
  3. The databases restore: Pocket ID's and shorti's SQLite files pass an integrity check, and Outline's dump loads into a throwaway Postgres. For NetBird, every SQLite database passes an integrity check, and the store still holds your account.

  It reports each result to Gatus, as `nightly backup` and `netbird backup`. Gatus alerts on a failure, and also if no result arrives for 26 hours.

The watchtower can only **read** the backups buckets (`backup.tf`). Every restic command runs with `--no-lock`, so it never writes, and it couldn't damage the backups even if it went wrong.

### One-time setup

1. **The VM:** `terraform apply`. Expect 4 to add: the VM, its DNS record, its dynamic group and its read-only policy. Nothing should change on the main VM.
2. **SSH:** add a host entry to `~/.ssh/config`, a copy of the main VM's with the new name:
   ```
   Host watchtower
     HostName watchtower.<domain>
     User ubuntu
     IdentityFile ~/.ssh/<key>.pub
     IdentitiesOnly yes
   ```
3. **Prepare the VM.** It adds swap, and leaves ports 80/443 closed, because the watchtower serves nothing publicly:
   ```sh
   ssh watchtower 'sudo OPEN_WEB_PORTS=no bash -s' < host/setup-vm.sh
   ```
4. **Secrets, in 1Password.** The ntfy topic acts as a password: anyone who knows it can read your alerts.
   ```sh
   op item create --vault=Private --category="Secure Note" --title="Watchtower" \
     "ntfy_topic[password]=alerts-$(openssl rand -hex 16)" \
     "push_token[password]=$(openssl rand -hex 32)"
   ```
5. **Alerts on your phone:** install the ntfy app and subscribe to the topic (`op read "op://Private/Watchtower/ntfy_topic"`). Send a test message to make sure it arrives:
   ```sh
   curl -d "Hello from the watchtower" "ntfy.sh/$(op read 'op://Private/Watchtower/ntfy_topic')"
   ```
6. **Deploy, then run the first backup check right away:**
   ```sh
   services/deploy.sh watchtower        # builds the check image on the VM; takes a few minutes on the micro
   ssh watchtower 'cd ~/services/watchtower && docker compose exec backup-check check.sh main'
   ```
   It should end with `== backup check passed: …`. Right after `terraform apply`, the new policy can take a few minutes to apply everywhere. If the check can't read the snapshots, wait and try again.

### Day to day

```sh
open http://watchtower.netbird.selfhosted:8080   # the Gatus dashboard, over NetBird
ssh watchtower 'cd ~/services/watchtower && docker compose logs --tail 50 backup-check'
ssh watchtower 'cd ~/services/watchtower && docker compose exec backup-check check.sh main'      # check the main VM's backups now
ssh watchtower 'cd ~/services/watchtower && docker compose exec backup-check check.sh netbird'   # or the NetBird VM's
```

To change what's monitored, edit `watchtower/gatus/config.yaml` and redeploy.

### Who watches the watchtower?

Nothing on the watchtower can tell you that the watchtower itself has stopped. Oracle may also reclaim an Always Free VM that stays mostly idle for a week, and this one mostly waits. So an outside service, [healthchecks.io](https://healthchecks.io) (free), expects to hear from it every day, and emails you when it doesn't.

backup-check pings it each morning: `/start` when the checks begin, then plain success, or `/fail` if a check failed. So you're told when the watchtower goes quiet, when a run hangs, and when a check fails.

1. In healthchecks.io, add a check with schedule **Cron** `0 6 * * *`, time zone **UTC**, grace time **1 hour**. (If you change `CHECK_TIME`, change the schedule to match.) Email alerts are on by default.
2. Put its ping URL in `WATCHTOWER_PING_URL` in `services/config.env`, then `services/deploy.sh watchtower`.
3. Ping it once from inside the container, which proves the setting arrived and the VM can reach healthchecks.io:
   ```sh
   ssh watchtower 'cd ~/services/watchtower && docker compose exec backup-check sh -c "wget -q -T 10 -O /dev/null \"\$WATCHTOWER_PING_URL\" && echo pinged"'
   ```
   The check turns green in healthchecks.io. From then on the daily run keeps it green.

## NetBird

The VPN's control server runs on the second Always Free AMD micro VM (`netbird.tf`). [NetBird](https://netbird.io) builds a WireGuard mesh between your devices. This server signs them in, tells them how to reach each other, and relays their traffic only when no direct connection is possible. The stack (`services/netbird/`) has three containers:

- **server:** NetBird's combined server: management, signal, relay and STUN in one process. Its config is written in `compose.yaml`, with the secrets filled in from 1Password.
- **dashboard:** the web UI, where you manage devices, users and access policies.
- **caddy:** a Caddy of its own that gets the HTTPS certificate for `netbird.<domain>`. It sends gRPC (HTTP/2 without TLS, `h2c`), the relay and the API to the server, and everything else to the dashboard.

Sign-in uses NetBird's built-in identity provider, and Pocket ID can be added as an extra way to sign in. Keep the built-in admin account even then: it still works when the main VM, and with it Pocket ID, is down.

### One-time setup

1. **The VM:** `terraform apply`. Expect 4 to add: the VM, its network security group, the group's STUN rule (UDP 3478) and its DNS record. `netbird_dns_name` must be `netbird.<domain>`.
2. **SSH:** add a `Host netbird` entry to `~/.ssh/config`, a copy of the watchtower's with the new name.
3. **Prepare the VM.** It keeps ports 80/443 open for Caddy, and also opens STUN's port:
   ```sh
   ssh netbird 'sudo OPEN_UDP_PORTS=3478 bash -s' < host/setup-vm.sh
   ```
4. **Secrets, in 1Password.** Never change `store_encryption_key` afterwards: it encrypts parts of the database, so a backup can't be read without the key it was made with.
   ```sh
   op item create --vault=Private --category="Secure Note" --title="NetBird" \
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

### Behind NetBird

Only `auth` (Pocket ID) and `netbird` itself face the internet. SSH on every VM, the wiki and shorti answer only over NetBird: the VMs join NetBird as peers, and NetBird's DNS sends your devices to the main VM's NetBird address for the private sites. Do it in this order, so there's always a way in:

1. **The firewalls:** `terraform apply` with `ssh_allowed_cidr = "0.0.0.0/0"` still in `terraform.tfvars`. It creates the Bastion, moves the web ports to network security groups and opens WireGuard's port; SSH stays open. Then test the Bastion once (see the main README's *Break-glass access*), so you know it works before you need it.
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
6. **The private sites:** under **DNS → Zones**, add one zone per private name, distributed to `admins`: zone `wiki.<domain>` with an A record `wiki.<domain>`, and the same for `shorti.<domain>` and `cloud.<domain>`, all pointing at the main VM's NetBird IP. One zone for the whole `<domain>` would route every name under it (`auth` too) through NetBird's DNS; one zone per name keeps NetBird's DNS out of everything else. Then set `MAIN_VM_PRIVATE_IP` in `config.env` (from `terraform output -raw services_config`) and deploy `edge` and `watchtower`. Check that the wiki loads with NetBird on, and shows *Only available over the VPN* with it off.
7. **Close SSH:** delete the `ssh_allowed_cidr` line from `terraform.tfvars`, then `terraform apply` again. SSH now answers only over NetBird, the Bastion and the VCN.

### Day to day

```sh
ssh netbird 'cd ~/services/netbird && docker compose logs --tail 50 server'
ssh netbird 'docker stats --no-stream'   # memory use on the 1 GB VM
netbird status -d                        # on a device: is each peer P2P (direct) or Relayed?
```

To update NetBird, change the image tags in `netbird/compose.yaml` and redeploy.

### NetBird's backups

Every night at 02:00 UTC, the stack's `backup` container copies NetBird's three SQLite databases with SQLite's online backup: `store.db` (accounts, devices, policies), `idp.db` (the built-in sign-in) and `events.db` (the activity log). restic then encrypts them, together with any other files in the data folder. The GeoLite location files are left out, because the server downloads them again. Retention is the same as the main VM's: 7 daily, 4 weekly and 6 monthly snapshots.

They go to a bucket of their own, `netbird-backups`. The NetBird VM is the most exposed one, so its policy (`backup.tf`) only lets it write there: if it were ever taken over, the main VM's backups would stay out of its reach. It uses the same restic password (the `Backups` item), so one secret opens both. The watchtower verifies these backups every day as well (see [Watchtower](#watchtower)).

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
