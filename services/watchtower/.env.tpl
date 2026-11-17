# Rendered by deploy.sh with `op inject`, which swaps each secret reference below
# for its value from 1Password. It reads comments too, so keep references out of them.
# Commit this file; never commit a rendered .env.
RESTIC_PASSWORD={{ op://Homelab/Backups/restic_password }}
NTFY_TOPIC={{ op://Homelab/Watchtower/ntfy_topic }}
GATUS_PUSH_TOKEN={{ op://Homelab/Watchtower/push_token }}
