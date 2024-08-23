{ config, lib, pkgs, ... }:

{
  options = {
  };

  config = {
      networking.firewall.checkReversePath = false;  # https://nixos.wiki/wiki/WireGuard#Setting_up_WireGuard_with_NetworkManager
  };
}   