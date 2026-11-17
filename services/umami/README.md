# Umami

[← All services](../README.md)

[Umami](https://umami.is) is privacy-friendly web analytics: page views, visitors and referrers, without cookies. It counts visits to the wiki, through Outline's built-in Umami integration, and to public websites, at `umami.<domain>`. Umami has its own accounts and no Pocket ID sign-in, so its dashboard and API are VPN-only. Only the two addresses a tracked site's visitors need are public: the tracker, `/script.js`, and the endpoint that receives page views, `/api/send` (see [the edge proxy](../edge/README.md#vpn-only-sites)). Its database is in the nightly backups, Gatus checks that the tracker loads, and it has a tile on Homepage.

## One-time setup

1. **DNS:** add `umami.<domain>` to `service_dns_names`, then `terraform apply`. Expect 1 to add.
2. **Secrets, in 1Password:**
   ```sh
   op item create --vault=Homelab --category="Secure Note" --title="Umami" \
     "app_secret[password]=$(openssl rand -hex 32)" \
     "two_factor_key[password]=$(openssl rand -hex 32)" \
     "postgres_password[password]=$(openssl rand -hex 24)"
   ```
3. **VPN-only DNS:** in NetBird, add the zone `umami.<domain>` with an A record `umami.<domain>` pointing at the main VM's NetBird IP, distributed to the same groups as the wiki's zone (see [Behind NetBird](../netbird/README.md#behind-netbird)).
4. **Deploy:** `services/deploy.sh umami`, then `services/deploy.sh edge` and `services/deploy.sh homepage`. Then, in this order, `services/deploy.sh backup` (it reaches into Umami's network, so it comes after), a backup by hand, and `services/deploy.sh watchtower` (its daily check expects Umami's database in the latest backup). [NetBox](../netbox/README.md#one-time-setup) step 5 has the commands.
5. **Change the default login right away.** Umami creates the account `admin` with the password `umami`, and everyone on the VPN can reach the sign-in page. Sign in at `https://umami.<domain>`, then under **Settings → Profile** set a new password (store it in the `Umami` item) and turn on two-factor sign-in.
6. **The website:** under **Settings → Websites → Add website**, add `wiki.<domain>` and copy its **Website ID**.
7. **Outline:** under **Settings → Integrations → Umami**, set the instance URL to `https://umami.<domain>/`, the script name to `script.js`, and the website ID from step 6. Outline adds Umami's address to its script allow-list by itself.

Browse the wiki, then watch Umami's **Realtime** view. Ad blockers may block the tracker; Umami's `TRACKER_SCRIPT_NAME` setting serves it under another name if that gets in the way.

## A public website

Add it under **Settings → Websites**, then put Umami's tag in the site's pages, with its website ID:

```html
<script defer src="https://umami.<domain>/script.js" data-website-id="<website ID>" data-domains="<the site's domain>" data-do-not-track="true"></script>
```

`data-domains` makes the tracker ignore copies of the site on other domains, and `data-do-not-track` respects visitors who ask not to be tracked. Umami sets no cookies and doesn't store IP addresses.

## Backups

Its database (websites, accounts and every recorded visit) is in the nightly backups, and the watchtower restores it every morning to test it. See [Restoring](../backup/README.md#restoring).
