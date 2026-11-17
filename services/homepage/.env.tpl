# Rendered by deploy.sh with `op inject`, which swaps each secret reference below
# for its value from 1Password. It reads comments too, so keep references out of them.
# Commit this file; never commit a rendered .env.
HOMEPAGE_AUTH_SECRET={{ op://Homelab/Homepage/auth_secret }}
HOMEPAGE_OIDC_CLIENT_ID={{ op://Homelab/Homepage/oidc_client_id }}
HOMEPAGE_OIDC_CLIENT_SECRET={{ op://Homelab/Homepage/oidc_client_secret }}
