After toying with pihole and unbound on containers, I wanted to see if there are performance differences between docker deployments and 'bare-metal' installs on the OS

dnsperf tests showed that baremetal installs perform better, assuming you turn off ratelimiting which is set on 1000 QPS by default in pihole.

based on the installation instructions on the Pihole website:
- Basic Pihole install https://docs.pi-hole.net/main/basic-install/
- unbound, Pihole as allround DNS solution https://docs.pi-hole.net/guides/dns/unbound/
- Assumes installation from a ~/pihole directory; change to your preference

![performance graph](./Pihole-Unbound%20performance%20tests.png) 
  
