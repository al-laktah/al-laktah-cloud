# Rendered by deploy.sh with `op inject`, which swaps each secret reference below
# for its value from 1Password. It reads comments too, so keep references out of them.
# Commit this file; never commit a rendered .env.
SECRET_KEY={{ op://Private/NetBox/secret_key }}
API_TOKEN_PEPPER={{ op://Private/NetBox/api_token_pepper }}
POSTGRES_PASSWORD={{ op://Private/NetBox/postgres_password }}
SUPERUSER_PASSWORD={{ op://Private/NetBox/admin_password }}
OIDC_CLIENT_ID={{ op://Private/NetBox/oidc_client_id }}
OIDC_CLIENT_SECRET={{ op://Private/NetBox/oidc_client_secret }}
