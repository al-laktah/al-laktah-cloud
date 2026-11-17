# Rendered by deploy.sh with `op inject`, which swaps each secret reference below
# for its value from 1Password. It reads comments too, so keep references out of them.
# Commit this file; never commit a rendered .env.
APP_SECRET={{ op://Homelab/Umami/app_secret }}
TWO_FACTOR_KEY={{ op://Homelab/Umami/two_factor_key }}
POSTGRES_PASSWORD={{ op://Homelab/Umami/postgres_password }}
