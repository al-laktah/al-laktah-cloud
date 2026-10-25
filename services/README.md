# Services

Docker Compose stacks that run on the VM, all behind one Caddy edge proxy.

| Stack | URL | What it is |
| --- | --- | --- |
| `edge/` | | Caddy edge proxy, and the only container that publishes ports (80, 443, 443/udp). Gets HTTPS certificates for every site in `edge/config/sites/` automatically |
| `pocket-id/` | `auth.<domain>` | [Pocket ID](https://pocket-id.org): a passkey-only OpenID Connect provider that signs you in to the other services |
| `outline/` | `wiki.<domain>` | [Outline](https://www.getoutline.com) wiki, with its Postgres and Redis |
| `backup/` | | Nightly encrypted [restic](https://restic.net) backups of every service's data to OCI Object Storage (see [Backups](#backups)) |

[shorti](https://github.com/al-laktah/shorti) also runs on the VM, but it is built and deployed from its own repo (see below). This repo only provides its DNS record and its site file in `edge/config/sites/`.

## How it fits together

- **DNS:** Terraform creates an A record for each hostname in `service_dns_names` (`terraform.tfvars`).
- **Routing:** the edge proxy terminates TLS and forwards each hostname to a container by name, over a shared external Docker network called `web`. Databases and caches stay on their own stack's private network.
- **Secrets:** they live in 1Password. Each stack commits an `.env.tpl` that contains only `op://` references. `deploy.sh` fills them in with `op inject` and writes the result straight to `.env` on the VM.
- **On the VM:** each stack lives in `~/services/<service>`, and its data is in named Docker volumes (`docker volume ls`).

## Prerequisites

- The VM is prepared by `setup-vm.sh`: Docker with the Compose plugin, the `ubuntu` user in the `docker` group, ports 80/443 open in the VM's firewall, and log rotation.
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
4. **The Outline OIDC client.** In Pocket ID, go to **OIDC Clients → Add**. Name it `Outline` and set the callback URL to `https://wiki.<domain>/auth/oidc.callback`. The client secret is shown **only once**, so store it right away:
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
3. Create `services/edge/config/sites/<name>.caddy`:
   ```
   <subdomain>.{$DOMAIN} {
   	reverse_proxy <container name on the web network>:<container port>
   }
   ```
4. Run `services/deploy.sh <name>`, then `services/deploy.sh edge`.

CI checks every folder that has a `compose.yaml` with `docker compose config`, using placeholder values for the `op://` references.

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
4. **The settings:** copy the output of `terraform output -raw backup_config` into `services/config.env`.
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
