# Outline

[← All services](../README.md)

The [Outline](https://www.getoutline.com) wiki at `wiki.<domain>`, with its Postgres and Redis. It's VPN-only: your devices reach it through a NetBird DNS zone (see [Behind NetBird](../netbird/README.md#behind-netbird)). Outline has no passwords; you sign in with [Pocket ID](../pocket-id/README.md).

## One-time setup

Set up [Pocket ID](../pocket-id/README.md#one-time-setup) first.

1. **DNS.** Make sure `wiki.<domain>` is in `service_dns_names`, then `terraform apply`.
2. **Secrets, in 1Password:**
   ```sh
   op item create --vault=Homelab --category="Secure Note" --title="Outline" \
     "secret_key[password]=$(openssl rand -hex 32)" \
     "utils_secret[password]=$(openssl rand -hex 32)" \
     "postgres_password[password]=$(openssl rand -hex 24)"
   ```
3. **The OIDC client.** In Pocket ID, go to **OIDC Clients → Add**. Name it `Outline`, set the callback URL to `https://wiki.<domain>/auth/oidc.callback`, and the logout callback URL to exactly `https://wiki.<domain>` (no trailing slash). Without that, signing out leaves you on Pocket ID's own logout page instead of back at Outline, which in the desktop app looks like nothing happened. The client secret is shown **only once**, so store it right away:
   ```sh
   op item edit Outline --vault=Homelab \
     "oidc_client_id[text]=<client id>" "oidc_client_secret[password]=<client secret>"
   ```
4. **Outline.**
   ```sh
   services/deploy.sh outline
   ```
   Open `https://wiki.<domain>` and choose **Continue with Pocket ID**. The first person to sign in creates the workspace and becomes its admin. Only users that exist in Pocket ID can sign in, and Pocket ID has no public sign-up.

## Settings worth knowing

- **The sign-in button** reads "Continue with" plus `SIGN_IN_NAME` from `config.env` (default "Pocket ID"). Keep it equal to Pocket ID's **Application Name**, and deploy `outline` again after changing it.
- **Logo, name and accent colour** are under **Settings → Details**. The logo must be a PNG or JPEG.
- **Visit statistics** come from [Umami](../umami/README.md), under **Settings → Integrations → Umami**.

## Updating

Bump the image tag in `compose.yaml` and deploy. Outline migrates its database when it starts, so run a backup first: `ssh <host> 'cd ~/services/backup && docker compose exec backup backup.sh'`.

## Backups

Its database and uploaded files are in the nightly backups. See [Restoring](../backup/README.md#restoring).
