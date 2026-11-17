# Edge proxy

[← All services](../README.md)

The [Caddy](https://caddyserver.com) reverse proxy in front of every site on the main VM, and the only container there that publishes ports (80, 443 and 443/udp). It gets and renews an HTTPS certificate for each site by itself, and forwards each hostname to a container by name, over the shared external Docker network `web`. Databases and caches stay on their own stack's private network.

- `config/Caddyfile` defines the `vpn_only` snippet and loads the sites.
- `config/sites/` has one file per site, with `{$DOMAIN}` standing for your domain. Deploying `edge` reloads Caddy, so a new or changed site goes live without a restart.
- On the `web` network, Caddy also answers as `auth.<domain>`. Other stacks' server-side sign-in calls to Pocket ID (Outline's, Homepage's, NetBox's) then reach it directly instead of looping out through the VM's public IP.

## VPN-only sites

A site file that starts with `import vpn_only` answers only NetBird addresses (`100.64.0.0/10`) and private ones (the VCN, for the watchtower's checks, and Docker's own networks). Everyone else gets a 403, *Only available over the VPN*. The name stays in public DNS, so its certificate keeps renewing; your devices reach the site through a NetBird DNS zone (see [Behind NetBird](../netbird/README.md#behind-netbird)).

Part of a site can be public while the rest stays private, with `handle` blocks: shorti's short links are public but creating links isn't (`shorti.caddy`), and Umami's tracker is public but its dashboard isn't (`umami.caddy`).

## Setup

The edge proxy is deployed first on a new VM, together with [Pocket ID](../pocket-id/README.md#one-time-setup). After that, run `services/deploy.sh edge` whenever a file in `config/` changes.
