# Pocket ID

[← All services](../README.md)

[Pocket ID](https://pocket-id.org) at `auth.<domain>`: a passkey-only OpenID Connect provider that signs you in to the other services. It's public, because you also sign in to NetBird with it. It has no public sign-up: only users you create can sign in.

These services sign in through it, each with an OIDC client of its own in Pocket ID: [Outline](../outline/README.md), [Homepage](../homepage/README.md), [NetBox](../netbox/README.md) and, optionally, [NetBird](../netbird/README.md).

## One-time setup

1. **DNS.** Make sure `auth.<domain>` is in `service_dns_names`, then `terraform apply`. Caddy can only get a certificate once the name resolves.
2. **Secret, in 1Password.** The value is generated on the spot and never shown:
   ```sh
   op item create --vault=Homelab --category="Secure Note" --title="Pocket ID" \
     "encryption_key[password]=$(openssl rand -base64 32)"
   ```
3. **The edge proxy and Pocket ID.**
   ```sh
   services/deploy.sh edge
   services/deploy.sh pocket-id
   ```
   Open `https://auth.<domain>/setup`, create your admin account and add your YubiKey as a passkey. Add a **second passkey** too (e.g. one stored in 1Password), so losing the YubiKey doesn't lock you out.

## Branding

Its name, accent colour, logos, favicon and sign-in background are under **Settings → Application Configuration**. Homepage shows the same favicon, logo and background (see [Homepage](../homepage/README.md)). If you change the **Application Name**, set `SIGN_IN_NAME` in `config.env` to match and redeploy `outline` and `netbox`, so their sign-in buttons use the same name.

## Lost every passkey?

On the VM, run `cd ~/services/pocket-id && docker compose exec pocket-id /app/pocket-id one-time-access-token <username>`. It prints a one-hour sign-in link; use it to add a new passkey.

## Backups

Its database and uploads are in the nightly backups. See [Restoring](../backup/README.md#restoring).
