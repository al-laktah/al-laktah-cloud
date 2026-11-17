# Services

Docker Compose stacks that run on the VMs. The main VM's stacks all sit behind one Caddy edge proxy. Each stack's folder has a README with its setup and day-to-day use.

| Stack | URL | What it is |
| --- | --- | --- |
| [`edge/`](edge/README.md) | | Caddy edge proxy, and the only container on the main VM that publishes ports (80, 443, 443/udp). Gets HTTPS certificates for every site in `edge/config/sites/` automatically |
| [`pocket-id/`](pocket-id/README.md) | `auth.<domain>` | [Pocket ID](https://pocket-id.org): a passkey-only OpenID Connect provider that signs you in to the other services |
| [`outline/`](outline/README.md) | `wiki.<domain>` | [Outline](https://www.getoutline.com) wiki, with its Postgres and Redis |
| [`homepage/`](homepage/README.md) | `cloud.<domain>` | [Homepage](https://gethomepage.dev): the start page listing the services, with sign-in through Pocket ID |
| [`netbox/`](netbox/README.md) | `netbox.<domain>` | [NetBox](https://netbox.dev): documentation of the network (IP addresses, devices, racks), with sign-in through Pocket ID |
| [`umami/`](umami/README.md) | `umami.<domain>` | [Umami](https://umami.is): cookieless visit statistics for the wiki and public websites |
| [`backup/`](backup/README.md) | | Nightly encrypted [restic](https://restic.net) backups of every service's data to OCI Object Storage, and how to restore them |
| [`watchtower/`](watchtower/README.md) | | Runs on the separate watchtower VM. [Gatus](https://github.com/TwiN/gatus) monitors the sites and certificates, and a daily job verifies the backups read-only |
| [`netbird/`](netbird/README.md) | `netbird.<domain>` | Runs on the separate NetBird VM. The [NetBird](https://netbird.io) VPN server and dashboard, behind a Caddy of its own. Its README also covers putting SSH and the private sites behind the VPN |

[shorti](https://github.com/al-laktah/shorti) also runs on the VM, but it is built and deployed from its own repo (see [below](#apps-with-their-own-repo-shorti)). This repo only provides its DNS record and its site file in `edge/config/sites/`.

## How it fits together

- **DNS:** Terraform creates an A record for each hostname in `service_dns_names` (`terraform.tfvars`).
- **Routing:** the [edge proxy](edge/README.md) terminates TLS and forwards each hostname to a container by name, over a shared external Docker network called `web`. Databases and caches stay on their own stack's private network.
- **VPN-only sites:** a site file that starts with `import vpn_only` answers only NetBird addresses (and the VCN, for the watchtower); everyone else gets a 403. `auth` stays public, because you sign in to NetBird with it. See [Behind NetBird](netbird/README.md#behind-netbird).
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

The script syncs the stack to `~/services/<service>`, writes its `.env` and runs `docker compose up -d`. Running it again is safe, so redeploy after every change. Deploying `edge` also reloads Caddy's config, so new sites go live without a restart. It refuses to sync into a folder that is a git checkout, so apps deployed from their own repo, like shorti, are never overwritten. The READMEs stay on your laptop, so editing one never restarts anything.

## Setting up from scratch

1. [Pocket ID](pocket-id/README.md), together with the edge proxy.
2. [Outline](outline/README.md), [Homepage](homepage/README.md), [NetBox](netbox/README.md) and [Umami](umami/README.md), in any order.
3. [Backups](backup/README.md), once the stacks that hold data are running.
4. The [watchtower](watchtower/README.md), after the first backup.
5. [NetBird](netbird/README.md), then [Behind NetBird](netbird/README.md#behind-netbird). Until its DNS zones exist, the VPN-only sites answer everyone with a 403.

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
4. For a VPN-only site, add a NetBird DNS zone for its name (see [Behind NetBird](netbird/README.md#behind-netbird)), and its name to the gatus container's `extra_hosts` in `watchtower/compose.yaml`.
5. Add a tile to `homepage/config/services.yaml`, with a `siteMonitor` at the container's address on the `web` network.
6. If it keeps data, add it to the [backups](backup/README.md) (the dump or volumes in `backup/`, the restore test in `watchtower/check/check.sh`, and the restore steps).
7. Write `services/<name>/README.md` and link it from the table above.
8. Run `services/deploy.sh <name>`, then deploy `edge`, `homepage` and `watchtower`.

CI checks every folder that has a `compose.yaml` with `docker compose config`, using placeholder values for the `op://` references.

## Updating a service

Bump the image tag in its `compose.yaml` and deploy. Apps with a database migrate it when they start, so run a backup first (see [Backups](backup/README.md#day-to-day)).

## Apps with their own repo (shorti)

shorti builds its images from source, so it is deployed from a checkout of its repo on the VM, not by `deploy.sh`:

```sh
ssh <host> 'cd ~/services/shorti && git pull && docker compose up -d --build'
```

Its frontend joins the `web` network as `shorti`, and `edge/config/sites/shorti.caddy` routes `shorti.<domain>` to it: short links are public, creating them is VPN-only. To bring it under `deploy.sh` later, have the shorti repo's CI publish Arm images to a registry (e.g. GHCR). Then a `services/shorti/compose.yaml` here can use `image:` instead of `build:`. Its data is in the nightly [backups](backup/README.md).
