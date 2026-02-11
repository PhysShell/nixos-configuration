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

## Tips

- `nix run nixpkgs#nix-prefetch-git` — get commit info (`rev` + `hash`) for `fetchFromGitHub`.
- Config can live outside `/etc/nixos`. Just run `nixos-rebuild switch --flake .#[host]` from the repo directory.
