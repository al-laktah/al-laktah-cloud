#!/bin/bash
# Prepares a fresh Ubuntu VM on Oracle Cloud for the Docker services in services/:
# updates, the VM's own firewall, Docker, log rotation and the shared "web" network.
# The services themselves, including the edge proxy, are deployed with
# services/deploy.sh afterwards.
#
# Run it from your laptop:  ssh <host> 'sudo bash -s' < host/setup-vm.sh
# For a VM that serves no websites (the watchtower), leave ports 80/443 closed:
#                            ssh <host> 'sudo OPEN_WEB_PORTS=no bash -s' < host/setup-vm.sh
# Running it again is safe, it only does what is still missing.
set -euo pipefail

OPEN_WEB_PORTS=${OPEN_WEB_PORTS:-yes}

if [ "$(id -u)" -ne 0 ]; then
	echo "Run this with sudo" >&2
	exit 1
fi

USER_NAME=${SUDO_USER:-ubuntu}
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
if [ -z "$USER_HOME" ]; then
	echo "User $USER_NAME does not exist" >&2
	exit 1
fi
SERVICES="$USER_HOME/services"

export DEBIAN_FRONTEND=noninteractive
apt_get() {
	apt-get -y -o DPkg::Lock::Timeout=600 \
		-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

echo "== Adding swap on small VMs"
# The 1 GB AMD micro can run out of memory while upgrading packages or building images
mem_mb=$(awk '/MemTotal/ { print int($2 / 1024) }' /proc/meminfo)
if [ "$mem_mb" -lt 2048 ] && [ -z "$(swapon --show --noheadings)" ]; then
	fallocate -l 2G /swapfile
	chmod 600 /swapfile
	mkswap /swapfile
	swapon /swapfile
	grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "== Installing updates"
apt_get update
apt_get upgrade
apt_get install unattended-upgrades ca-certificates curl

# Security updates already install by themselves, this also reboots at 4:00 when one needs it
cat > /etc/apt/apt.conf.d/52automatic-reboot <<'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF

if [ "$OPEN_WEB_PORTS" = yes ]; then
	echo "== Opening ports 80 and 443"
	# Oracle's Ubuntu images block everything but SSH on the VM itself, on top of the security list.
	# The rules file is edited by hand instead of saved, so Docker's own rules never end up in it.
	RULES=/etc/iptables/rules.v4
	for rule in "-p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT" \
		"-p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT" \
		"-p udp -m state --state NEW -m udp --dport 443 -j ACCEPT"; do
		# shellcheck disable=SC2086
		if ! iptables -C INPUT $rule 2>/dev/null; then
			reject=$(iptables -L INPUT --line-numbers -n | awk '$2 == "REJECT" { print $1; exit }')
			iptables -I INPUT "${reject:-1}" $rule
		fi
		if [ -f "$RULES" ] && ! grep -qF -- "-A INPUT $rule" "$RULES"; then
			sed -i "/^-A INPUT -j REJECT/i -A INPUT $rule" "$RULES"
		fi
	done
else
	echo "== Leaving ports 80 and 443 closed (OPEN_WEB_PORTS=$OPEN_WEB_PORTS)"
fi

echo "== Installing Docker"
if ! command -v docker >/dev/null; then
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	chmod a+r /etc/apt/keyrings/docker.asc
	# shellcheck disable=SC1091
	codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
		> /etc/apt/sources.list.d/docker.list
	apt_get update
	apt_get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
usermod -aG docker "$USER_NAME"

# Rotate container logs so they can't fill up the disk
if [ ! -f /etc/docker/daemon.json ]; then
	echo '{ "log-driver": "local" }' > /etc/docker/daemon.json
	systemctl restart docker
fi

echo "== Preparing for the services"
# Every service joins this network so the edge proxy can reach it by name
docker network inspect web >/dev/null 2>&1 || docker network create web

# deploy.sh puts each stack in ~/services/<name>
mkdir -p "$SERVICES"
chown "$USER_NAME:" "$SERVICES"

echo
echo "Done. Next, from your laptop: services/deploy.sh edge, then the other stacks."
echo "Log out and back in once to use docker without sudo."
if [ -f /var/run/reboot-required ]; then
	echo "Some updates need a reboot: sudo reboot"
fi
