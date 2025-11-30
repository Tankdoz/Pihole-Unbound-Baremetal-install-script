#!/bin/bash
# Pi-hole + Unbound baremetal installer
# Tested on Debian/Ubuntu/Raspberry Pi OS

set -e

echo "=== Pi-hole + Unbound baremetal installer ==="

# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Basis dependencies
sudo apt install -y curl git wget lsb-release apt-transport-https ca-certificates

# 3. Install Pi-hole
echo "Checking Pi-hole version..."
if command -v pihole >/dev/null 2>&1; then
    echo "Pi-hole is already installed. Running update check..."
    if sudo pihole updatePihole; then
        echo "Pi-hole is up-to-date. Skipping reinstallation."
        SKIP_PIHOLE_INSTALL=true
    else
        echo "Pi-hole update failed or not installed correctly. Proceeding with installation..."
        SKIP_PIHOLE_INSTALL=false
    fi
else
    echo "Pi-hole not found. Proceeding with installation..."
    SKIP_PIHOLE_INSTALL=false
fi

if [ "$SKIP_PIHOLE_INSTALL" != "true" ]; then
    echo "Installing Pi-hole..."
    # Clean up any old installer directory
    if [ -d "$HOME/pihole/Pi-hole" ]; then
        rm -rf "$HOME/pihole/Pi-hole"
    fi
    git clone --depth 1 https://github.com/pi-hole/pi-hole.git ~/pihole/Pi-hole
    cd ~/pihole/Pi-hole/automated\ install/
    sudo bash basic-install.sh --unattended
else
    echo "Skipping Pi-hole installation."
fi

# 4. Install Unbound
sudo apt install -y unbound

# 5. Configuratiebestand for Unbound
sudo mkdir -p /etc/unbound/unbound.conf.d
cat <<'EOF' | sudo tee /etc/unbound/unbound.conf.d/pi-hole.conf
server:
    # If no logfile is specified, syslog is used
    logfile: "/var/log/unbound/unbound.log"
    log-time-ascii: yes
    verbosity: 1

    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes

    # May be set to no if you don't have IPv6 connectivity
    do-ip6: no

    # You want to leave this to no unless you have *native* IPv6. With 6to4 and
    # Terredo tunnels your web browser should favor IPv4 for the same reasons
    prefer-ip6: no

    # Use this only when you downloaded the list of primary root servers!
    # If you use the default dns-root-data package, unbound will find it automatically
    #root-hints: "/var/lib/unbound/root.hints"

    # Trust glue only if it is within the server's authority
    harden-glue: yes

    # Require DNSSEC data for trust-anchored zones, if such data is absent, the zone becomes BOGUS
    harden-dnssec-stripped: yes

    # Don't use Capitalization randomization as it known to cause DNSSEC issues sometimes
    # see https://discourse.pi-hole.net/t/unbound-stubby-or-dnscrypt-proxy/9378 for further details
    use-caps-for-id: no

    # Reduce EDNS reassembly buffer size.
    # IP fragmentation is unreliable on the Internet today, and can cause
    # transmission failures when large DNS messages are sent via UDP. Even
    # when fragmentation does work, it may not be secure; it is theoretically
    # possible to spoof parts of a fragmented DNS message, without easy
    # detection at the receiving end. Recently, there was an excellent study
    # >>> Defragmenting DNS - Determining the optimal maximum UDP response size for DNS <<<
    # by Axel Koolhaas, and Tjeerd Slokker (https://indico.dns-oarc.net/event/36/contributions/776/)
    # in collaboration with NLnet Labs explored DNS using real world data from the
    # the RIPE Atlas probes and the researchers suggested different values for
    # IPv4 and IPv6 and in different scenarios. They advise that servers should
    # be configured to limit DNS messages sent over UDP to a size that will not
    # trigger fragmentation on typical network links. DNS servers can switch
    # from UDP to TCP when a DNS response is too big to fit in this limited
    # buffer size. This value has also been suggested in DNS Flag Day 2020.
    edns-buffer-size: 1232

    # Perform prefetching of close to expired message cache entrie
    # This only applies to domains that have been frequently queried
    prefetch: yes

    # One thread should be sufficient, can be increased on beefy machines. In reality for most users running on small networks or on a single machine, it should be unnecessary to see>
    num-threads: 1

    # Ensure kernel buffer is large enough to not lose messages in traffic spikes
    so-rcvbuf: 1m

    # Ensure privacy of local IP ranges
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10

    # Ensure no reverse queries to non-public IP ranges (RFC6303 4.2)
    private-address: 192.0.2.0/24
    private-address: 198.51.100.0/24
    private-address: 203.0.113.0/24
    private-address: 255.255.255.255/32
    private-address: 2001:db8::/32
EOF

# 6. Start unbound with new configuration
echo "6. starting unbound"
sudo service unbound restart

# 7. Create log dir and file and set permissions
echo "7. create logfile"
sudo mkdir -p /var/log/unbound
sudo touch /var/log/unbound/unbound.log
sudo chown unbound /var/log/unbound/unbound.log

# 8. Add AppArmor exception for unbound
echo "8. adding AppArmor exception"
sudo mkdir -p /etc/apparmor.d/local
# Append logfile permission to Unbound profile
sudo tee -a /etc/apparmor.d/local/usr.sbin.unbound > /dev/null <<'EOF'
/var/log/unbound/unbound.log rw,
EOF
# Reload AppArmor profiles so changes take effect
sudo apparmor_parser -r /etc/apparmor.d/usr.sbin.unbound
sudo service apparmor restart

# 9. Fix so-rcvbuf warning for Unbound
echo "9. fix so-rcvbuf"
# Increase kernel receive buffer size to match Unbound's request (1 MB)

# Check current value
current=$(sysctl -n net.core.rmem_max)
echo "Current net.core.rmem_max = $current"

# Temporarily set to 1048576 (1 MB)
echo "increasing net.core.rmem_max temporarily"
sudo sysctl -w net.core.rmem_max=1048576

# Make permanent via sysctl.d
echo "increasing net.cor.rmem_max permanently in sysctl"
sudo tee /etc/sysctl.d/99-unbound.conf > /dev/null <<'EOF'
net.core.rmem_max=1048576
EOF
# Apply change
echo "applying change"
sudo systemctl restart systemd-sysctl
# Restart Unbound to apply new buffer size
echo "restarting unbound"
sudo service unbound restart

# 10. Post-install: add user to pihole group, set unbound as upstream DNS and set password
#!/bin/bash

echo "Post-install: add user to pihole group"
sudo usermod -aG pihole "$USER"

echo "Configuring Pi-hole upstreams to Unbound..."
# Stop FTL om race conditions te voorkomen
sudo systemctl stop pihole-FTL

# Vervang upstreams array binnen [dns] sectie
sudo awk '
  BEGIN {in_dns=0; saw_upstreams=0}
  /^\[/ {
    if (in_dns && !saw_upstreams) {
      print "  upstreams = ["
      print "    \"127.0.0.1#5335\""
      print "  ]"
    }
    in_dns = ($0 ~ /^\[dns\]/)
    saw_upstreams=0
    print; next
  }
  in_dns && $0 ~ /^[[:space:]]*upstreams[[:space:]]*=/ {
    print "  upstreams = ["
    print "    \"127.0.0.1#5335\""
    print "  ]"
    saw_upstreams=1
    while (getline line) {
      if (line ~ /\]/) break
    }
    next
  }
  {print}
  END {
    if (in_dns && !saw_upstreams) {
      print "  upstreams = ["
      print "    \"127.0.0.1#5335\""
      print "  ]"
    }
  }
' /etc/pihole/pihole.toml | sudo tee /etc/pihole/pihole.toml.tmp >/dev/null && sudo mv /etc/pihole/pihole.toml.tmp /etc/pihole/pihole.toml

echo "Configured upstreams in pihole.toml:"
sudo awk '/^\[dns\]/,/^\[/{print}' /etc/pihole/pihole.toml | sed -n "/upstreams/,/]/p"

echo "Restarting FTL..."
sudo systemctl start pihole-FTL

echo "Set Pi-hole password"
sudo pihole setpassword "Pihole007!"

echo "=== Runtime forwarding check ==="
echo "Performing test query..."
dig en.wikipedia.org @127.0.0.1 -p 53

echo "=== Installation complete ==="
echo "Pi-hole is installed and configured to use Unbound as local recursive resolver."
echo

# 12. Test pihole and unbound
echo
echo "=== Testing DNSSEC validation with Unbound ==="
echo

# Test domain with broken DNSSEC (should fail)
if dig fail01.dnssec.works @127.0.0.1 -p 5335 +dnssec | grep -q "SERVFAIL"; then
    echo "DNSSEC OK: fail01.dnssec.works returned SERVFAIL (invalid signature rejected)."
else
    echo "WARNING: fail01.dnssec.works did not return SERVFAIL."
fi

# Test domain with valid DNSSEC (should succeed with AD flag)
if dig +ad dnssec.works @127.0.0.1 -p 5335 | grep -q "NOERROR"; then
    if dig +ad dnssec.works @127.0.0.1 -p 5335 | grep -q "flags:.*ad"; then
        echo "DNSSEC OK: dnssec.works returned NOERROR with AD flag (Authentic Data)."
    else
        echo "WARNING: dnssec.works returned NOERROR but missing AD flag."
    fi
else
    echo "WARNING: dnssec.works did not return NOERROR."
fi

# Run a test query
dig en.wikipedia.org @127.0.0.1

# Show last few lines of Pi-hole log
sudo tail -n 5 /var/log/pihole/pihole.log

echo
echo "If you see 'forwarded ... to 127.0.0.1#5335' and a reply, Pi-hole is using Unbound upstream."

