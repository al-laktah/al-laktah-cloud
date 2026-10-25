#!/usr/bin/env bash
# Deploys one service stack to the VM:  services/deploy.sh <service>
#
#   1. Syncs services/<service>/ to ~/services/<service>/ on the VM.
#   2. Writes ~/services/<service>/.env: DOMAIN from config.env, plus .env.tpl with
#      its op:// references filled in by 1Password (`op inject`). The secrets go
#      straight over SSH and never touch the local disk.
#   3. Runs `docker compose up -d` there (and reloads Caddy's config for edge).
set -euo pipefail

cd "$(dirname "$0")"
service="${1:?usage: services/deploy.sh <service>}"
[[ -f "$service/compose.yaml" ]] || { echo "no stack at services/$service/compose.yaml" >&2; exit 1; }

source ./config.env # DEPLOY_HOST, DEPLOY_SSH_KEY, DOMAIN

# Render secrets first, so a failed `op inject` can't leave a half-written .env behind.
env_content="DOMAIN=$DOMAIN"
if [[ -f "$service/.env.tpl" ]]; then
  env_content+=$'\n'"$(op inject -i "$service/.env.tpl")"
fi

# Reuse one SSH connection for the whole deploy, so a hardware key is touched once.
ssh_opts=(-o ControlMaster=auto -o "ControlPath=$HOME/.ssh/cm-%C" -o ControlPersist=60)
if [[ -n ${DEPLOY_SSH_KEY:-} ]]; then
  # Offer only this key. Otherwise the agent offers whatever it holds, and the VM
  # may reject all of them before the right one comes up.
  ssh_opts+=(-i "$DEPLOY_SSH_KEY" -o IdentitiesOnly=yes)
fi
remote() { ssh "${ssh_opts[@]}" "$DEPLOY_HOST" "$@"; }

dir="services/$service" # relative to the remote home directory

# Apps deployed from their own git checkout (like shorti) must never be synced over:
# --delete would wipe their source. If SSH itself fails, set -e stops the deploy here.
is_checkout=$(remote "if test -d $dir/.git; then echo yes; else echo no; fi")
if [[ $is_checkout == yes ]]; then
  echo "~/$dir on the VM is a git checkout, refusing to sync over it" >&2
  exit 1
fi

remote "mkdir -p $dir && { docker network inspect web >/dev/null 2>&1 || docker network create web; }"

# --delete keeps the VM in step with the repo; .env is excluded so it survives.
# Service data lives in named Docker volumes, never inside ~/services/<service>.
rsync -a --delete --exclude .env --exclude .env.tpl -e "ssh ${ssh_opts[*]}" "$service/" "$DEPLOY_HOST:$dir/"
printf '%s\n' "$env_content" | remote "umask 077 && cat > $dir/.env"

remote "cd $dir && docker compose pull --quiet && docker compose up -d --remove-orphans"

# `up -d` leaves a running Caddy alone when only its config files changed.
if [[ $service == edge ]]; then
  remote "cd $dir && docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile"
fi

remote "cd $dir && docker compose ps"
