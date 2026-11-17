# Rendered by deploy.sh with `op inject`, which swaps each secret reference below
# for its value from 1Password. It reads comments too, so keep references out of them.
# Commit this file; never commit a rendered .env.
SECRET_KEY={{ op://Homelab/NetBox/secret_key }}
API_TOKEN_PEPPER={{ op://Homelab/NetBox/api_token_pepper }}
POSTGRES_PASSWORD={{ op://Homelab/NetBox/postgres_password }}
SUPERUSER_PASSWORD={{ op://Homelab/NetBox/admin_password }}
OIDC_CLIENT_ID={{ op://Homelab/NetBox/oidc_client_id }}
OIDC_CLIENT_SECRET={{ op://Homelab/NetBox/oidc_client_secret }}
