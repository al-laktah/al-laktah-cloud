# Rendered by deploy.sh with `op inject`, which swaps each secret reference below
# for its value from 1Password. It reads comments too, so keep references out of them.
# Commit this file; never commit a rendered .env.
#
# Without the restic password the backups can't be decrypted, so keep it safe.
RESTIC_PASSWORD={{ op://Private/Backups/restic_password }}
POSTGRES_PASSWORD={{ op://Private/Outline/postgres_password }}
