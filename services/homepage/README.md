# Homepage

[← All services](../README.md)

The start page at `cloud.<domain>`, built with [Homepage](https://gethomepage.dev): one tile per service, each with a status dot, plus the main VM's CPU, memory and disk. It's VPN-only like the wiki, and asks you to sign in with Pocket ID.

The **Gatus** tile shows how many checks are up and down, read from Gatus on the watchtower across the VCN (`WATCHTOWER_PRIVATE_IP` in `config.env`; the watchtower's firewall lets only the main VM in). Clicking it opens the Gatus dashboard over NetBird.

Everything on the page comes from the YAML in `config/`: `services.yaml` for the tiles, `widgets.yaml` for the top row, `bookmarks.yaml` for the links, `settings.yaml` for the layout. Edit and redeploy; `deploy.sh`'s fingerprint restarts Homepage when a file changes. Write `{{HOMEPAGE_VAR_DOMAIN}}` instead of your domain, so the files stay generic.

The look: `custom.css` recolours Homepage with [Catppuccin](https://catppuccin.com/palette), Latte in light mode and Mocha in dark mode. The page starts in your system's mode, and the toggle at the bottom switches. The favicon, the logo in the top row and the dark-mode background are the ones uploaded to Pocket ID (**Application Configuration → Images**), so the brand is set in one place. Until you upload your own, Homepage shows Pocket ID's defaults.

## One-time setup

1. **Pocket ID:** add an OIDC client called Homepage, with callback URL `https://cloud.<domain>/api/auth/callback/homepage-oidc`. Homepage lets in anyone Pocket ID accepts, so allow only your own user group on the client.
2. **Secrets, in 1Password**, with the client's ID and secret from step 1:
   ```sh
   op item create --vault=Homelab --category="Secure Note" --title="Homepage" \
     "auth_secret[password]=$(openssl rand -base64 32)" \
     "oidc_client_id[text]=<client ID>" \
     "oidc_client_secret[password]=<client secret>"
   ```
3. **VPN-only DNS:** in NetBird, add the zone `cloud.<domain>` with an A record `cloud.<domain>` pointing at the main VM's NetBird IP, distributed to `admins` (see [Behind NetBird](../netbird/README.md#behind-netbird)). `cloud.<domain>` is the VM's own public record (`dns_name`), so its certificate renews as usual.
4. **Deploy:** `services/deploy.sh homepage`, then `services/deploy.sh edge` for the new site, and `services/deploy.sh watchtower` for its check.
