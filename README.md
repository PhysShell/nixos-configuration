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

## Tips

- `nix run nixpkgs#nix-prefetch-git` — get commit info (`rev` + `hash`) for `fetchFromGitHub`.
- Config can live outside `/etc/nixos`. Just run `nixos-rebuild switch --flake .#[host]` from the repo directory.
