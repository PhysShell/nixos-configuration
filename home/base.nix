# home/base.nix – baseline Home Manager config imported by every host
#
# CLI tools and baseline user programs.
# Desktop / GUI packages live in home/desktop.nix.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./terminal.nix
  ];

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
}
