# home/base.nix – baseline Home Manager config imported by every host
#
# CLI tools, shell (zsh), prompt (starship), fuzzy-find, etc.
# Desktop / GUI packages live in home/desktop.nix.
{ config, pkgs, lib, ... }:

{
  programs.home-manager.enable = true;

  # ── Packages available on every machine ───────────────────────
  home.packages = with pkgs; [
    wget
    git
    htop

    # modern CLI replacements
    eza        # ls
    bat        # cat
    ripgrep    # grep
    fd         # find
    delta      # diff
    gitui      # TUI git client
    tree
    curl

    devenv
    claude-code
  ];

  # ── Bash (always available as fallback) ───────────────────────
  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  # ── Git ───────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    signing.format = null;
    settings = {
      user.name = "PhysShell";
      user.email = "mouse.kcsource@gmail.com";
      pull.rebase = true;
      init.defaultBranch = "main";
      color.ui = "auto";
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  # ── Starship prompt (bash + zsh) ─────────────────────────────
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      # /mnt/c (drvfs) in WSL can make git status slower than Starship's default timeout.
      command_timeout = 5000;
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

  # ── fzf  (Ctrl-R / Ctrl-T / Alt-C) ──────────────────────────
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f";
    fileWidgetCommand = "fd --type f";
    changeDirWidgetCommand = "fd --type d";
    changeDirWidgetOptions = [ "--preview 'tree -C {} | head -200'" ];
  };

  # ── zoxide  (z <pattern>) ───────────────────────────────────
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  # ── direnv + nix-direnv ──────────────────────────────────────
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  # ── atuin  (smart history search) ────────────────────────────
  programs.atuin = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = false;
      filter_mode = "host";
    };
  };

  # ── Zsh ──────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    initContent = ''
      bindkey -v
      bindkey -M viins '^f' autosuggest-accept
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
}
