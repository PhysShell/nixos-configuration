# common/core.nix – settings shared by every host
{ pkgs, ... }:

{
  # Enable flakes & the new CLI everywhere
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Zsh as the login shell (actual user assignment is per-host)
  programs.zsh.enable = true;
}
