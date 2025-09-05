{ config, pkgs, ... }:

let out = "${config.xdg.stateHome}/vulnix"; in
{
  age.identityPaths = [ "/home/physshell/.ssh/agenix_id_ed25519" ];

  age.secrets.private_ssh_config = {
    file = ./secrets/private-ssh-config.age;
    mode = "600";
  };

  home.username = "physshell";
  home.homeDirectory = "/home/physshell";

  home.packages = with pkgs; [
    vscode.fhs
    code-cursor
    wget
    git
    htop
    
    (lutris.override {
      extraPkgs = pkgs: [];
      extraLibraries = pkgs: [];
    })
    wineWowPackages.stable
    winetricks

    microsoft-edge
    transmission_4-gtk

    vulnix
  ];

  programs.bash.enable = true;
  programs.firefox.enable = true;
  programs.home-manager.enable = true;
  
  programs.git = {
    enable = true;
    userName = "PhysShell";
    userEmail = "mouse.kcsource@gmail.com";
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ config.age.secrets.private_ssh_config.path ];
    matchBlocks = {
      "*" = {
        identitiesOnly = true;
        addKeysToAgent = "yes";
      };
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = [ "~/.ssh/id_ed25519_github_home_pc" ];
        identitiesOnly = true;
        addKeysToAgent = "yes";
      };
    };
  };

 systemd.user.services.vulnix-scan = {
    Unit.Description = "Daily vulnix scan (user)";
    Service = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.coreutils}/bin/mkdir -p '${out}'
        ${pkgs.vulnix}/bin/vulnix --system --json > '${out}/'$(date +%F).json
      '';
    };
  };

  systemd.user.timers.vulnix-scan = {
    Unit.Description = "Timer: vulnix scan daily";
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      Unit = "vulnix-scan.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  home.stateVersion = "25.05";
}