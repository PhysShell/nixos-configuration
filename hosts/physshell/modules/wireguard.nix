{ ... }:

{
  config = {
    networking.firewall.checkReversePath = false; # Required for full-tunnel WireGuard routes.

    # Old full-tunnel peer is intentionally disabled while testing the VPS path.
    # If you need it later, uncomment the block and keep autostart = false.
    #
    # networking.wg-quick.interfaces.wg0 = {
    #   autostart = false;
    #   address = [ "10.0.0.21/32" ];
    #   dns = [ "10.116.5.2" ];
    #   privateKeyFile = "/etc/wireguard/physshell-wg0.key";
    #
    #   peers = [
    #     {
    #       publicKey = "IdFfEXkthhOBWjX/f+AOOjGqzBXVF8vldb/MhjVKpDc=";
    #       allowedIPs = [ "0.0.0.0/0" ];
    #       endpoint = "185.239.146.19:39548";
    #     }
    #   ];
    # };

    networking.wg-quick.interfaces.wg-vps = {
      address = [ "10.66.66.2/24" ];
      privateKeyFile = "/etc/wireguard/home-vps.key";

      peers = [{
        publicKey = "ejrlajXOKcM4Swax8OSkIWqpsHl+dD14HncNlM1C1iU=";
        endpoint = "66.245.220.84:51820";
        allowedIPs = [ "10.66.66.1/32" ];
        persistentKeepalive = 25;
      }];
    };

    networking.nat = {
      enable = true;
      externalInterface = "wlo1";
      internalInterfaces = [ "wg-vps" ];
    };

    networking.firewall.trustedInterfaces = [ "wg-vps" ];

    systemd.tmpfiles.rules = [
      "d /etc/wireguard 0700 root root -"
    ];
  };
}
