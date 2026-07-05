{ pkgs, ... }:

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
      postUp = ''
        endpoint_file=/etc/wireguard/wg-vps.endpoint
        if [ ! -s "$endpoint_file" ]; then
          echo "missing WireGuard VPS endpoint file: $endpoint_file" >&2
          exit 1
        fi
        endpoint="$(${pkgs.coreutils}/bin/cat "$endpoint_file")"
        ${pkgs.wireguard-tools}/bin/wg set wg-vps peer 9Cyc036RWhelIUqSqo/gF3uKzQe0yBwnkj/pEi8pAG8= endpoint "$endpoint"
      '';

      peers = [{
        publicKey = "9Cyc036RWhelIUqSqo/gF3uKzQe0yBwnkj/pEi8pAG8=";
        allowedIPs = [ "10.66.66.1/32" ];
        persistentKeepalive = 25;
      }];
    };

    networking.nat = {
      enable = true;
      externalInterface = null;
      internalInterfaces = [ "wg-vps" ];
    };

    networking.firewall.trustedInterfaces = [ "wg-vps" ];

    services.unbound = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        server = {
          interface = [ "10.66.66.2" ];
          access-control = [ "10.66.66.0/24 allow" ];

          do-ip4 = true;
          do-ip6 = false;
          do-udp = true;
          do-tcp = true;

          hide-identity = true;
          hide-version = true;
          prefetch = true;
          qname-minimisation = true;
        };
      };
    };

    systemd.services.unbound = {
      after = [ "wg-quick-wg-vps.service" ];
      wants = [ "wg-quick-wg-vps.service" ];
    };

    systemd.tmpfiles.rules = [
      "d /etc/wireguard 0700 root root -"
      "z /etc/wireguard/wg-vps.endpoint 0600 root root -"
    ];
  };
}
