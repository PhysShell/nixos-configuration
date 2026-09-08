{
  description = "Unified NixOS flake — desktop (physshell) & WSL";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, claude-code, agenix, nixos-wsl, ... }:
  let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
    claudeOverlay = claude-code.overlays.default;

    # Whitelist of allowed unfree packages (used on the desktop host)
    unfreeNames = [
      "nvidia-x11" "nvidia-settings"
      "steam" "steam-unwrapped"
      "code" "vscode" "cursor" "microsoft-edge"
      "claude-code"
    ];
    allowUnfree = pkg: builtins.elem (lib.getName pkg) unfreeNames;
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfreePredicate = allowUnfree;
    };
  in
  {
    packages.${system}.route-probe = pkgs.writeShellApplication {
      name = "route-probe";
      runtimeInputs = with pkgs; [
        coreutils
        curl
        globalping-cli
        gnugrep
        iputils
        mtr
        netcat-openbsd
        openssh
      ];
      text = builtins.readFile ./scripts/route-probe.sh;
    };

    apps.${system}.route-probe = {
      type = "app";
      program = "${self.packages.${system}.route-probe}/bin/route-probe";
    };

    devShells.${system}.default = pkgs.mkShell {
      packages = [
        self.packages.${system}.route-probe
      ] ++ (with pkgs; [
        bind.dnsutils
        curl
        globalping-cli
        gnused
        iproute2
        iputils
        jq
        mtr
        netcat-openbsd
        openssh
        traceroute
        wireguard-tools
        xray
      ]);

      shellHook = ''
        echo "route tools: route-probe, globalping, mtr, traceroute, wg, xray"
        echo "try: nix develop -c ./scripts/reality-client.sh"
        echo "try: nix run .#route-probe -- 66.245.220.84"
      '';
    };

    # ── Desktop (physical machine) ──────────────────────────────
    nixosConfigurations.physshell = nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = { inherit allowUnfree inputs; };

      modules = [
        ./hosts/physshell/configuration.nix

        # Overlay adds pkgs.claude-code
        ({ ... }: { nixpkgs.overlays = [ claudeOverlay ]; })

        # System-wide allowUnfree predicate
        ({ ... }: { nixpkgs.config.allowUnfreePredicate = allowUnfree; })

        ./modules/maintenance.nix
        ({ ... }: { maintenance.enable = true; })

        home-manager.nixosModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bkp";

          home-manager.users.physshell = {
            imports = [
              agenix.homeManagerModules.default
              ./hosts/physshell/home.nix
              ./modules/hm-maintenance.nix
              ({ ... }: { hmMaintenance.enable = true; })
            ];
          };
        }
      ];
    };

    # ── WSL ─────────────────────────────────────────────────────
    nixosConfigurations.wsl = nixpkgs.lib.nixosSystem {
      inherit system;

      specialArgs = { inherit inputs; };

      modules = [
        nixos-wsl.nixosModules.default
        ./hosts/wsl/configuration.nix

        # System-wide allowUnfree predicate
        ({ ... }: { nixpkgs.config.allowUnfreePredicate = allowUnfree; })

        ./modules/maintenance.nix
        ({ ... }: {
          maintenance.enable = true;
          maintenance.gc.enable = true;
          maintenance.optimise.enable = true;
        })

        # nix.settings.min-free cannot help under WSL: it reads free space from
        # the filesystem, and the filesystem is a growing VHDX that reports a
        # terabyte free while the Windows volume behind it has gigabytes left.
        # This guard asks Windows for the real number through interop instead.
        ./modules/wsl-disk-guard.nix
        ({ ... }: {
          wslDiskGuard = {
            enable = true;
            hostDrive = "D";
            freeThresholdGiB = 10;
            compactTask = "CompactWslDisk";
          };
        })

        # Overlay adds pkgs.claude-code
        ({ ... }: { nixpkgs.overlays = [ claudeOverlay ]; })

        home-manager.nixosModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "bkp";

          home-manager.users.nixos = {
            imports = [
              ./hosts/wsl/home.nix
            ];
          };
        }
      ];
    };
  };
}
