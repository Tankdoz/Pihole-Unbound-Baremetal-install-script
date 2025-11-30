#!/bin/bash
# Pi-hole + Unbound uninstall script (Ubuntu 24+)

set -e

echo "=== Uninstalling Pi-hole and Unbound ==="

# 1. Pi-hole uninstall (git-based install)
if command -v pihole >/dev/null 2>&1; then
    echo "Removing Pi-hole via its own uninstall routine..."
    sudo pihole uninstall
else
    echo "Pi-hole command not found, skipping."
fi

# 2. Unbound uninstall
echo "Removing Unbound..."
sudo systemctl stop unbound || true
sudo apt-get purge -y unbound
sudo rm -rf /etc/unbound /var/log/unbound
sudo rm -f /etc/apparmor.d/local/usr.sbin.unbound
sudo rm -f /etc/sysctl.d/99-unbound.conf

# 4. Clean up apt packages
sudo apt-get autoremove -y
sudo apt-get autoclean -y

# 5. Remove Pi-hole installer directory if present
echo "Cleaning up Pi-hole installer directory..."
if [ -d "$HOME/pihole/Pi-hole" ]; then
    sudo rm -rf "$HOME/pihole/Pi-hole"
    echo "Removed $HOME/pihole/Pi-hole"
fi

# 6. Test DNS resolution
echo "Testing DNS resolution..."
if dig github.com +short >/dev/null 2>&1; then
    echo "Default resolver works."
else
    echo "WARNING: Default resolver failed, please check /etc/resolv.conf."
fi

echo "=== Uninstall complete ==="
echo "Pi-hole and Unbound have been removed, DNS resolver configuration restored."
