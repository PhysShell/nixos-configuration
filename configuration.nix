{ config, pkgs, ... }:

{
  imports = [ ./gandicloud.nix ];

  networking = {
#    nftables = {
#      enable = true;
#      ruleset = ''
#        table ip nat {
#          chain PREROUTING {
#            type nat hook prerouting priority dstnat; policy accept;
#            tcp dport 80 redirect to :8080
#            tcp dport 443 redirect to :8443
#          }
#        }
#      '';
#  };
  firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 8008];
  };
};

    users.users.dendrite_user = {
        isNormalUser = true;
    	description = "dendrite_user";
    	extraGroups = [ "networkmanager" "wheel" ];
	group = "dendrite_user"; 
	packages = with pkgs; [
		git
	];
    };

    users.groups.dendrite_user = {};
}