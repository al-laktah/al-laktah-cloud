# Rendered by deploy.sh with `op inject`, which swaps each secret reference below
# for its value from 1Password. It reads comments too, so keep references out of them.
# Commit this file; never commit a rendered .env.
# The store key encrypts parts of NetBird's database. Never change it: a restored
# backup can't be read without the key it was written with.
NETBIRD_AUTH_SECRET={{ op://Private/NetBird/auth_secret }}
NETBIRD_SESSION_KEY={{ op://Private/NetBird/session_cookie_key }}
NETBIRD_STORE_KEY={{ op://Private/NetBird/store_encryption_key }}
# The same restic password as the main VM's backups, so one secret opens both.
RESTIC_PASSWORD={{ op://Private/Backups/restic_password }}
