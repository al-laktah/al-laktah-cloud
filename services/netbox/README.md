# NetBox

[← All services](../README.md)

[NetBox](https://netbox.dev) documents the network: IP addresses and prefixes, VLANs, devices and racks. It runs on the main VM at `netbox.<domain>`, VPN-only like the wiki, with its own Postgres and Redis and a worker for background jobs. You sign in with Pocket ID. A local `admin` account is the way in when Pocket ID is down.

## One-time setup

1. **DNS:** add `netbox.<domain>` to `service_dns_names` in `terraform.tfvars`, then `terraform apply`. Expect 1 to add: the DNS record. The site stays VPN-only; the public record is what lets Caddy get its certificate.
2. **Pocket ID:** add an OIDC client called NetBox, with callback URL `https://netbox.<domain>/oauth/complete/oidc/` (with the trailing slash). Everyone the client accepts gets a NetBox account, so allow only your own user group.
3. **Secrets, in 1Password**, with the client's ID and secret from step 2. NetBox wants its secret key and API token pepper at least 50 characters long:
   ```sh
   op item create --vault=Homelab --category="Secure Note" --title="NetBox" \
     "secret_key[password]=$(openssl rand -base64 48)" \
     "api_token_pepper[password]=$(openssl rand -base64 48)" \
     "postgres_password[password]=$(openssl rand -hex 24)" \
     "admin_password[password]=$(openssl rand -base64 24)" \
     "oidc_client_id[text]=<client ID>" \
     "oidc_client_secret[password]=<client secret>"
   ```
   Keep `$` out of these values: Docker Compose would read it as a variable.
4. **VPN-only DNS:** in NetBird, add the zone `netbox.<domain>` with an A record `netbox.<domain>` pointing at the main VM's NetBird IP, distributed to `admins` (see [Behind NetBird](../netbird/README.md#behind-netbird)).
5. **Deploy, in this order:**
   ```sh
   services/deploy.sh netbox    # the first start sets up the database: a few minutes
   services/deploy.sh edge
   services/deploy.sh homepage
   services/deploy.sh backup    # it reaches into NetBox's network and volumes, so after netbox
   ssh <host> 'cd ~/services/backup && docker compose exec backup backup.sh'
   services/deploy.sh watchtower
   ```
   The backup should end with `== backup finished`. Deploy the watchtower only after it: its daily check expects NetBox's database in the latest backup, and fails until one has it.
6. **Your account:** open `https://netbox.<domain>` and sign in with Pocket ID. NetBox creates your user, but with no permissions. Sign out, sign in as `admin` with `admin_password` from 1Password, then under **Admin → Users** edit your user and make it a **superuser**. From then on, use Pocket ID.

## Backups

Its database, uploads, reports and scripts are in the nightly backups, and the watchtower restores the database every morning to test it. See [Restoring](../backup/README.md#restoring).
