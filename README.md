# NixOS Configuration (Desktop + WSL)

Unified multi-host flake system configuration.

## Structure

```
.
├── flake.nix                         # Entry point: both hosts defined here
├── common/                           # Shared NixOS system modules
│   ├── core.nix                      #   nix settings, flakes, zsh
│   └── docker.nix                    #   rootless Docker
├── home/                             # Shared Home Manager modules
│   ├── base.nix                      #   CLI tools, shell, git, starship…
│   └── desktop.nix                   #   GUI apps, fonts, vulnix (desktop only)
├── modules/                          # Opt-in NixOS/HM modules with options
│   ├── maintenance.nix               #   nix store GC, optimise, pin inputs
│   └── hm-maintenance.nix            #   HM generations cleanup
└── hosts/
    ├── physshell/                     # Desktop (physical machine, Plasma 6)
    │   ├── configuration.nix
    │   ├── hardware-configuration.nix
    │   ├── home.nix                  #   imports home/{base,desktop}.nix + agenix/SSH
    │   ├── secrets.nix
    │   ├── modules/                  #   virtualisation, wireguard
    │   └── secrets/
    └── wsl/                          # WSL 2
        ├── configuration.nix         #   imports common/* + WSL-specific
        └── home.nix                  #   imports home/base.nix (no desktop)
```

## Building

**Desktop (physical machine):**
```bash
sudo nixos-rebuild switch --flake .#physshell
```

**WSL:**
```bash
sudo nixos-rebuild switch --flake .#wsl
```

## Update package sources

```bash
nix flake lock
```

## Tier 2 smoke test

For the full home residential exit relay runbook, see
[`docs/home-exit-relay.md`](docs/home-exit-relay.md).

Use the helper script to test the VPS → WireGuard → home-exit chain layer by layer:

```bash
sudo -v
VPS_SSH=root@your-vps \
HOME_WG_IFACE=wg-vps \
VPS_WG_IFACE=wg-vps \
HOME_WG_IP=10.66.66.2 \
VPS_WG_IP=10.66.66.1 \
XRAY_SOCKS=127.0.0.1:10808 \
./scripts/tier2-smoke.sh
```

If Xray traffic uses a policy-routing mark, add `ROUTE_MARK=0x66`.
The initial `sudo -v` lets the script read local WireGuard handshake metadata without prompting mid-run.

## Desktop proxy client

Start a local SOCKS5 client for app/browser proxy mode:

```bash
nix develop -c ./scripts/reality-client.sh
```

It listens on `127.0.0.1:20809` and forwards traffic through the Reality VPS and then the WireGuard home exit.

Test from another terminal:

```bash
curl -x socks5h://127.0.0.1:20809 https://api.ipify.org
```

Point browser/app SOCKS5 settings at `127.0.0.1:20809`.

## Route probing

Enter the network toolbox:

```bash
nix develop
```

Probe candidate VPS routes from China and from the current local connection:

```bash
nix run .#route-probe -- <VPS_IPV4>
```

Useful knobs:

```bash
CHINA_SOURCES="China,China Telecom,China Unicom,China Mobile" \
GLOBALPING_LIMIT=5 \
RUN_MTR=1 \
nix run .#route-probe -- <VPS_IPV4>
```

Set `CHINA_SOURCES=""` to skip China-side probes and only check the local or SSH legs.
Set `IP_VERSION=6` or `IP_VERSION=both` to compare IPv6 routes for hosts that have IPv6.

For the currently configured VPS, also test the return leg back home:

```bash
VPS_SSH=root@<VPS_IPV4> \
SSH_OPTS="-F /dev/null -i ./vps_relay_key -o IdentitiesOnly=yes" \
HOME_TARGET=<HOME_IPV4> \
nix run .#route-probe -- <VPS_IPV4>
```

## Tips

- `nix run nixpkgs#nix-prefetch-git` — get commit info (`rev` + `hash`) for `fetchFromGitHub`.
- Config can live outside `/etc/nixos`. Just run `nixos-rebuild switch --flake .#[host]` from the repo directory.
