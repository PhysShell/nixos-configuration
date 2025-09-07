{ config, pkgs, lib, ... }:

let
  out = "${config.xdg.stateHome}/vulnix";
in
{
  age.identityPaths = [ "/home/physshell/.ssh/agenix_id_ed25519" ];

  age.secrets.private_ssh_config = {
    file = ./secrets/private-ssh-config.age;
    mode = "600";
  };

  home.username = "physshell";
  home.homeDirectory = "/home/physshell";

  home.packages = with pkgs; [
    # user packages
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

    # handy tools
    eza
    bat
    ripgrep
    fd
    delta
    gitui
    tree

    # set JetBrainsMono Nerd Font in your Konsole profile
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerd-fonts.fira-code

    # middle mouse key paste by keyboard
    xdotool
    (pkgs.writeShellScriptBin "mouse-middle-click" ''
      ${pkgs.xdotool}/bin/xdotool click 2
    '')
  ];

  # Keep Bash enabled — can always return with the `bash` command
  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  programs.firefox.enable = true;
  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "PhysShell";
    userEmail = "mouse.kcsource@gmail.com";

    # pretty diffs/logs via delta
    delta.enable = true;
    extraConfig = {
      pull.rebase = true;
      init.defaultBranch = "main";
      color.ui = "auto";
    };
  };

  # IMPORTANT: the agent is already running here — do not enable programs.ssh.startAgent to avoid spawning multiple agents
  services.ssh-agent.enable = true;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    # git push don't work with code.fhs - https://github.com/nix-community/home-manager/issues/322
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

  # pretty prompt (bash+zsh)
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      username = {
        style_user = "blue bold";
        style_root = "red bold";
        format = "[$user]($style) ";
        show_always = true;
      };
      hostname = {
        ssh_only = false;
        ssh_symbol = "🌐 ";
        format = "on [$hostname](bold red) ";
        trim_at = ".local";
      };
      directory.truncation_length = 4;
      git_branch.format = "on [$symbol$branch]($style) ";
      git_status.disabled = false;
    };
  };

  # Ctrl-R (history), Ctrl-T (files), Alt-C (cd to dir) — fuzzy finder
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f";
    fileWidgetCommand = "fd --type f";
    changeDirWidgetCommand = "fd --type d";
    # mini tree preview on Alt-C
    changeDirWidgetOptions = [ "--preview 'tree -C {} | head -200'" ];
  };

  # "cd on steroids": z <pattern>
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  # Auto-environments per folder (.envrc / flake) — run `direnv allow` once
  # programs.direnv = {
  #   enable = true;
  #   nix-direnv.enable = true;
  # };

  # History with search (replaces Ctrl-R with "smart" search)
  programs.atuin = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = false;
      filter_mode = "host";
    };
  };

  # ====== Zsh + zsh-shortcut-git ======
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    initContent = ''
      # zi() { cd "$(zoxide query -i)"; }
      bindkey -v
    '';

    plugins = [
      {
        name = "zsh-shortcut-git";
        src = pkgs.fetchFromGitHub {
          owner = "zh30";
          repo  = "zsh-shortcut-git";
          rev   = "f1d0d6f929d72749c7aa3535a98949bec5e516af";
          hash  = "sha256-LP5StJwATK4L0GqnL97ATfSNQYe54+E/9ursS8KRiJ8=";
        };
        file = "zsh-shortcut-git.plugin.zsh";
      }
    ];
  };

  # ====== vulnix ======
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

  # local fontconfig setup for user
  fonts.fontconfig.enable = true;

  home.stateVersion = "25.05";
}
