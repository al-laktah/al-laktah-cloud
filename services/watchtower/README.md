# Watchtower

[← All services](../README.md)

A separate, Always Free AMD micro VM (`watchtower.tf`) watches the main VM from outside, because a VM that hangs can't report on itself. It runs two containers:

- **Gatus** checks `wiki`, `cloud`, `netbox`, `auth`, `shorti`, `umami` (its public tracker) and `netbird` over HTTPS and the main VM's SSH port, every minute. The VPN-only sites and SSH are checked across the VCN, at the main VM's private IP (`MAIN_VM_PRIVATE_IP`); the public sites over the internet, the way visitors reach them. It sends an alert to your phone through [ntfy](https://ntfy.sh) after 3 failed checks in a row, or when a certificate has less than 10 days left. It sends another when things recover.
- **backup-check** verifies the backups of both VMs every day at 06:00 UTC, first the main VM's, then the NetBird VM's:
  1. The latest backup is less than 26 hours old.
  2. The repository passes `restic check`, which also downloads and verifies a different quarter of all backup data each day (all of it every 4 days).
  3. The databases restore: Pocket ID's and shorti's SQLite files pass an integrity check, and the dumps of Outline, NetBox and Umami load into a throwaway Postgres (NetBox's must hold at least one user, Umami's at least one website). For NetBird, every SQLite database passes an integrity check, and the store still holds your account.

  It reports each result to Gatus, as `nightly backup` and `netbird backup`. Gatus alerts on a failure, and also if no result arrives for 26 hours.

The watchtower can only **read** the backups buckets (`backup.tf`). Every restic command runs with `--no-lock`, so it never writes, and it couldn't damage the backups even if it went wrong.

The Gatus dashboard is published on port 8080. The watchtower's firewall lets in only the main VM (for Homepage's Gatus tile); your devices reach the dashboard over NetBird, which that firewall never sees.

## One-time setup

1. **The VM:** `terraform apply`. Expect 4 to add: the VM, its DNS record, its dynamic group and its read-only policy. Nothing should change on the main VM.
2. **SSH:** add a host entry to `~/.ssh/config`, a copy of the main VM's with the new name:
   ```
   Host watchtower
     HostName watchtower.<domain>
     User ubuntu
     IdentityFile ~/.ssh/<key>.pub
     IdentitiesOnly yes
   ```
3. **Prepare the VM.** It adds swap, and leaves ports 80/443 closed, because the watchtower serves nothing publicly:
   ```sh
   ssh watchtower 'sudo OPEN_WEB_PORTS=no bash -s' < host/setup-vm.sh
   ```
4. **Secrets, in 1Password.** The ntfy topic acts as a password: anyone who knows it can read your alerts.
   ```sh
   op item create --vault=Homelab --category="Secure Note" --title="Watchtower" \
     "ntfy_topic[password]=alerts-$(openssl rand -hex 16)" \
     "push_token[password]=$(openssl rand -hex 32)"
   ```
5. **Alerts on your phone:** install the ntfy app and subscribe to the topic (`op read "op://Homelab/Watchtower/ntfy_topic"`). Send a test message to make sure it arrives:
   ```sh
   curl -d "Hello from the watchtower" "ntfy.sh/$(op read 'op://Homelab/Watchtower/ntfy_topic')"
   ```
6. **Deploy, then run the first backup check right away:**
   ```sh
   services/deploy.sh watchtower        # builds the check image on the VM; takes a few minutes on the micro
   ssh watchtower 'cd ~/services/watchtower && docker compose exec backup-check check.sh main'
   ```
   It should end with `== backup check passed: …`. Right after `terraform apply`, the new policy can take a few minutes to apply everywhere. If the check can't read the snapshots, wait and try again.

## Day to day

```sh
open http://watchtower.netbird.selfhosted:8080   # the Gatus dashboard, over NetBird
ssh watchtower 'cd ~/services/watchtower && docker compose logs --tail 50 backup-check'
ssh watchtower 'cd ~/services/watchtower && docker compose exec backup-check check.sh main'      # check the main VM's backups now
ssh watchtower 'cd ~/services/watchtower && docker compose exec backup-check check.sh netbird'   # or the NetBird VM's
```

To change what's monitored, edit `gatus/config.yaml` and redeploy.

## Who watches the watchtower?

Nothing on the watchtower can tell you that the watchtower itself has stopped. Oracle may also reclaim an Always Free VM that stays mostly idle for a week, and this one mostly waits. So an outside service, [healthchecks.io](https://healthchecks.io) (free), expects to hear from it every day, and emails you when it doesn't.

backup-check pings it each morning: `/start` when the checks begin, then plain success, or `/fail` if a check failed. So you're told when the watchtower goes quiet, when a run hangs, and when a check fails.

1. In healthchecks.io, add a check with schedule **Cron** `0 6 * * *`, time zone **UTC**, grace time **1 hour**. (If you change `CHECK_TIME`, change the schedule to match.) Email alerts are on by default.
2. Put its ping URL in `WATCHTOWER_PING_URL` in `services/config.env`, then `services/deploy.sh watchtower`.
3. Ping it once from inside the container, which proves the setting arrived and the VM can reach healthchecks.io:
   ```sh
   ssh watchtower 'cd ~/services/watchtower && docker compose exec backup-check sh -c "wget -q -T 10 -O /dev/null \"\$WATCHTOWER_PING_URL\" && echo pinged"'
   ```
   The check turns green in healthchecks.io. From then on the daily run keeps it green.
