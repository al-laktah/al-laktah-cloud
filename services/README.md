# Services

Docker Compose stacks that run on the VM, all behind one Caddy edge proxy.

| Stack | URL | What it is |
| --- | --- | --- |
| `edge/` | | Caddy edge proxy, and the only container that publishes ports (80, 443, 443/udp). Gets HTTPS certificates for every site in `edge/config/sites/` automatically |
| `pocket-id/` | `auth.<domain>` | [Pocket ID](https://pocket-id.org): a passkey-only OpenID Connect provider that signs you in to the other services |
| `outline/` | `wiki.<domain>` | [Outline](https://www.getoutline.com) wiki, with its Postgres and Redis |

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

## Backups (not automated yet)

All service data lives in Docker volumes on the VM's boot volume. **Rebuilding the VM (`terraform apply -replace=...`) deletes it.** Until there are automated backups to Object Storage, take dumps by hand:

```sh
ssh <host> 'cd ~/services/outline && docker compose exec -T postgres pg_dump -U outline outline' > outline-$(date +%F).sql
```

Outline's uploaded files are in the `outline_files` volume, and Pocket ID's database (users, passkeys, OIDC clients) is in `pocket-id_data`. shorti's links are in `shorti_shorti-data`.
