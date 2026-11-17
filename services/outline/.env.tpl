# Rendered by deploy.sh with `op inject`, which swaps each secret reference below
# for its value from 1Password. It reads comments too, so keep references out of them.
# Commit this file; never commit a rendered .env.
SECRET_KEY={{ op://Homelab/Outline/secret_key }}
UTILS_SECRET={{ op://Homelab/Outline/utils_secret }}
POSTGRES_PASSWORD={{ op://Homelab/Outline/postgres_password }}
OIDC_CLIENT_ID={{ op://Homelab/Outline/oidc_client_id }}
OIDC_CLIENT_SECRET={{ op://Homelab/Outline/oidc_client_secret }}
