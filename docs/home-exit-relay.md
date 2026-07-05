# Home Exit Relay

This document captures the VPS Reality -> WireGuard -> home residential exit setup.
The goal is that client traffic enters the VPS, but public websites see the home ISP IPv4.

## Topology

```text
client / Hiddify
  -> VLESS Reality on VPS:443
  -> Xray outbound with fwmark 0x66
  -> VPS policy table 100
  -> WireGuard wg-vps
  -> home NixOS 10.66.66.2
  -> home ISP IPv4
```

Addresses used by the current setup:

```text
VPS public IPv4: <VPS_IPV4>
VPS WG IP:       10.66.66.1
home WG IP:      10.66.66.2
WG interface:    wg-vps
Xray SOCKS:      127.0.0.1:10808 on the VPS
Xray mark:       0x66 / decimal 102
route table:     100
route pref:      10066
```

Secrets are intentionally not documented here. The scripts generate/read them on the hosts.
The VPS WireGuard endpoint is stored outside the repo in `/etc/wireguard/wg-vps.endpoint`.

## Home NixOS

Home side is declared in `hosts/physshell/modules/wireguard.nix`.

It provides:

- WireGuard peer `wg-vps` with `10.66.66.2/24`;
- NAT from `wg-vps` out through `wlo1`;
- trusted firewall interface `wg-vps`;
- Unbound on `10.66.66.2:53` for VPS/client DNS queries over WireGuard.

Apply it:

```bash
sudo nixos-rebuild switch --flake .#physshell
```

Check local DNS for the VPS:

```bash
nix shell nixpkgs#bind -c dig @10.66.66.2 api.ipify.org A +short
```

Store the VPS WireGuard endpoint outside the repo:

```bash
sudo install -d -m 0700 /etc/wireguard
printf '%s\n' '<VPS_IPV4>:51820' | sudo tee /etc/wireguard/wg-vps.endpoint >/dev/null
sudo chmod 0600 /etc/wireguard/wg-vps.endpoint
```

## VPS Bootstrap

For a fresh Debian VPS:

```bash
VPS_SSH=root@<VPS_IPV4> \
SSH_OPTS="-F /dev/null -i ./hetzner_relay -o IdentitiesOnly=yes" \
./scripts/vps-debian-relay-bootstrap.sh
```

The bootstrap installs WireGuard, Xray, UFW, and policy routing.

Important routing behavior:

- marked IPv4 traffic routes to `wg-vps`;
- marked IPv6 traffic is `unreachable`, so Xray cannot leak through the VPS IPv6;
- Xray runs with the capability needed for `sockopt.mark`.

## Reality Reset

Regenerate/apply the Xray Reality config:

```bash
VPS_SSH=root@<VPS_IPV4> \
SSH_OPTS="-F /dev/null -i ./hetzner_relay -o IdentitiesOnly=yes" \
PROFILE_NAME=hetzner-home-exit-yahoo \
./scripts/vps-reality-reset.sh
```

The script prints Hiddify links. Prefer the raw-type fallback link when a client understands it.

The Xray config intentionally uses a strict leak-resistant profile:

- Xray DNS resolves through home Unbound: `10.66.66.2:53`;
- client DNS port `53` is redirected to home DNS;
- DNS-over-TLS port `853` is blocked;
- UDP/443 (QUIC) is blocked;
- marked IPv6 is blocked at the VPS policy-route level.

Blocking QUIC can make some sites feel slower on the first load, because browsers fall back to TCP/TLS. Keep it enabled for leak-sensitive testing.

## Smoke Test

Run the full server-side smoke:

```bash
VPS_SSH=root@<VPS_IPV4> \
SSH_OPTS="-F /dev/null -i ./hetzner_relay -o IdentitiesOnly=yes" \
ROUTE_MARK=0x66 \
./scripts/tier2-smoke.sh
```

Expected results:

```text
ok: marked traffic routes through wg-vps
ok: marked IPv6 traffic is blocked
ok: VPS Xray SOCKS public IPv4: <home IPv4>
ok: Xray egress matches expected home IP
warnings=0 failures=0
```

## Hiddify Client Settings

Critical client-side settings:

- service mode: VPN/TUN mode, not browser-only proxy mode;
- routing/region: `Any` / `Любой`;
- avoid region-specific rules like `Russia`, because they can route local/RU domains directly;
- Secure DNS in the browser: off while testing;
- IPv6-only mode: off;
- if there is an IPv6 disable/prefer IPv4 option, prefer IPv4 or disable IPv6 for this profile.

The important bug found during testing:

```text
Hiddify Region = Russia
```

caused `2ip.ru` to bypass the tunnel and show the mobile hotspot IPv4.
Changing the region to:

```text
Hiddify Region = Any / Любой
```

made the client route consistently through the profile.

## Leak Tests

Good checks:

```text
https://browserleaks.com/ip
https://browserleaks.com/dns
https://api.ipify.org
https://ifconfig.co
```

`2ip.ru` is useful as a hostile/regional-rule test, but it is noisy: ads and tracking domains create many extra requests.

Watch Xray while testing:

```bash
VPS_SSH=root@<VPS_IPV4> \
SSH_OPTS="-F /dev/null -i ./hetzner_relay -o IdentitiesOnly=yes" \
WATCH_FILTER='2ip|<SUSPICIOUS_SITE_IPV4>|home-out|home-dns|block|accepted tcp:\[' \
./scripts/vps-xray-watch.sh
```

Interpretation:

```text
[vless-reality >> home-out]   traffic entered Xray and should exit through home
[vless-reality -> home-dns]   DNS was redirected to home Unbound
[vless-reality -> block]      blocked by strict leak policy
```

If a site opens but there is no matching VPS log entry, the client is bypassing the tunnel.

## Windows Debug Commands

Resolve a suspicious site:

```powershell
Resolve-DnsName 2ip.ru -Type A
```

Check direct HTTP behavior:

```powershell
curl.exe -4 https://api.ipify.org
curl.exe -4 https://ifconfig.co
curl.exe -4 -v https://2ip.ru/
```

If Wireshark is needed, use:

```text
ip.addr == <SUSPICIOUS_SITE_IPV4> or ip.addr == <VPS_IPV4>
```

Expected:

- traffic to `<VPS_IPV4>:443` is normal;
- direct traffic to a destination site IP, such as `<SUSPICIOUS_SITE_IPV4>`, indicates a client bypass.

## Operational Notes

Keep the strict server-side protections unless performance matters more than leak resistance.

If a site is slow:

- first check whether Hiddify is in `Any` / global mode;
- then check `vps-xray-watch.sh` for repeated `block` lines;
- only consider relaxing QUIC after leak tests stay clean.

Do not disable the marked IPv6 block unless the home exit also has a properly routed residential IPv6 path.
