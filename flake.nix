{
  description = "A portable, customizable Caddy binary with popular plugins built in";

  nixConfig = {
    extra-substituters = [ "https://caddy-plugins-flake.cachix.org" ];
    extra-trusted-public-keys = [ "caddy-plugins-flake.cachix.org-1:HoaZQpWz4ESnl8Rch6/wlGd5xiZ55LlMKFTxc4M6SO4=" ];
  };

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Read the pre-calculated vendor hashes
      hashes = builtins.fromJSON (builtins.readFile ./hashes.json);

      # Helper to build Caddy with a specific set of plugins
      buildCaddy = pkgs: plugins: hash: (pkgs.caddy.withPlugins {
        inherit plugins hash;
      }).overrideAttrs (old: {
        # Disable post-build version tag checks so we can use @latest safely
        doInstallCheck = false;
      });
    in
    {
      # Export the library helper for 100% flexible custom combinations
      lib = {
        mkCaddy = { pkgs, plugins, hash }: buildCaddy pkgs plugins hash;
      };

      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          # Individual DNS provider variants (for lightweight wildcard ACME challenges)
          cloudflare = buildCaddy pkgs [ "github.com/caddy-dns/cloudflare@latest" ] hashes.cloudflare;
          route53 = buildCaddy pkgs [ "github.com/caddy-dns/route53@latest" ] hashes.route53;
          gandi = buildCaddy pkgs [ "github.com/caddy-dns/gandi@latest" ] hashes.gandi;
          digitalocean = buildCaddy pkgs [ "github.com/caddy-dns/digitalocean@latest" ] hashes.digitalocean;
          duckdns = buildCaddy pkgs [ "github.com/caddy-dns/duckdns@latest" ] hashes.duckdns;

          # Individual utility and security variants
          ratelimit = buildCaddy pkgs [ "github.com/mholt/caddy-ratelimit@latest" ] hashes.ratelimit;
          dynamicdns = buildCaddy pkgs [ "github.com/mholt/caddy-dynamicdns@latest" ] hashes.dynamicdns;
          security = buildCaddy pkgs [ "github.com/greenpau/caddy-security@latest" ] hashes.security;
          l4 = buildCaddy pkgs [ "github.com/mholt/caddy-l4@latest" ] hashes.l4;
          cache = buildCaddy pkgs [ "github.com/caddyserver/cache-handler@latest" ] hashes.cache;
          waf = buildCaddy pkgs [ "github.com/corazawaf/coraza-caddy/v2@latest" ] hashes.waf;

          # Full package bundling ALL plugins together
          full = buildCaddy pkgs [
            "github.com/caddy-dns/cloudflare@latest"
            "github.com/caddy-dns/route53@latest"
            "github.com/caddy-dns/gandi@latest"
            "github.com/caddy-dns/digitalocean@latest"
            "github.com/caddy-dns/duckdns@latest"
            "github.com/mholt/caddy-ratelimit@latest"
            "github.com/mholt/caddy-dynamicdns@latest"
            "github.com/greenpau/caddy-security@latest"
            "github.com/mholt/caddy-l4@latest"
            "github.com/caddyserver/cache-handler@latest"
            "github.com/corazawaf/coraza-caddy/v2@latest"
          ]
            hashes.full;

          default = full;
        }
      );

      # Native Nix test checks to verify compilation and Caddyfile configuration validation
      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          caddy-cloudflare = self.packages.${system}.cloudflare;
          caddy-route53 = self.packages.${system}.route53;
          caddy-gandi = self.packages.${system}.gandi;
          caddy-digitalocean = self.packages.${system}.digitalocean;
          caddy-duckdns = self.packages.${system}.duckdns;
          caddy-ratelimit = self.packages.${system}.ratelimit;
          caddy-dynamicdns = self.packages.${system}.dynamicdns;
          caddy-security = self.packages.${system}.security;
          caddy-l4 = self.packages.${system}.l4;
          caddy-cache = self.packages.${system}.cache;
          caddy-waf = self.packages.${system}.waf;
          caddy-full = self.packages.${system}.full;
        in
        {
          test-cloudflare = pkgs.runCommand "test-cloudflare" { } ''
            ${caddy-cloudflare}/bin/caddy list-modules | grep "dns.providers.cloudflare"
            cat <<'EOF' > Caddyfile
            http://localhost:8080 {
              tls {
                dns cloudflare abcdefghijklmnopqrstuvwxyz0123456789ABCD
              }
              respond "Hello"
            }
            EOF
            ${caddy-cloudflare}/bin/caddy validate --adapter caddyfile --config Caddyfile
            touch $out
          '';

          test-route53 = pkgs.runCommand "test-route53" { } ''
            ${caddy-route53}/bin/caddy list-modules | grep "dns.providers.route53"
            cat <<'EOF' > Caddyfile
            http://localhost:8080 {
              tls {
                dns route53
              }
              respond "Hello"
            }
            EOF
            ${caddy-route53}/bin/caddy validate --adapter caddyfile --config Caddyfile
            touch $out
          '';

          test-gandi = pkgs.runCommand "test-gandi" { } ''
            ${caddy-gandi}/bin/caddy list-modules | grep "dns.providers.gandi"
            cat <<'EOF' > Caddyfile
            http://localhost:8080 {
              tls {
                dns gandi dummy-gandi-token-value
              }
              respond "Hello"
            }
            EOF
            ${caddy-gandi}/bin/caddy validate --adapter caddyfile --config Caddyfile
            touch $out
          '';

          test-digitalocean = pkgs.runCommand "test-digitalocean" { } ''
            ${caddy-digitalocean}/bin/caddy list-modules | grep "dns.providers.digitalocean"
            cat <<'EOF' > Caddyfile
            http://localhost:8080 {
              tls {
                dns digitalocean dummy-digitalocean-token-value
              }
              respond "Hello"
            }
            EOF
            ${caddy-digitalocean}/bin/caddy validate --adapter caddyfile --config Caddyfile
            touch $out
          '';

          test-duckdns = pkgs.runCommand "test-duckdns" { } ''
            ${caddy-duckdns}/bin/caddy list-modules | grep "dns.providers.duckdns"
            cat <<'EOF' > Caddyfile
            http://localhost:8080 {
              tls {
                dns duckdns dummy-duckdns-token-value
              }
              respond "Hello"
            }
            EOF
            ${caddy-duckdns}/bin/caddy validate --adapter caddyfile --config Caddyfile
            touch $out
          '';

          test-ratelimit = pkgs.runCommand "test-ratelimit" { } ''
            ${caddy-ratelimit}/bin/caddy list-modules | grep "http.handlers.rate_limit"
            cat <<'EOF' > Caddyfile
            {
              order rate_limit before basicauth
            }
            http://localhost:8080 {
              rate_limit {
                zone custom_zone {
                  key {remote_ip}
                  events 10
                  window 1m
                }
              }
              respond "Hello"
            }
            EOF
            ${caddy-ratelimit}/bin/caddy validate --adapter caddyfile --config Caddyfile
            touch $out
          '';

          test-dynamicdns = pkgs.runCommand "test-dynamicdns" { } ''
            ${caddy-dynamicdns}/bin/caddy list-modules | grep "dynamic_dns"
            touch $out
          '';

          test-security = pkgs.runCommand "test-security" { } ''
            ${caddy-security}/bin/caddy list-modules | grep "security"
            cat <<'EOF' > Caddyfile
            {
              security {
                local identity store localdb {
                  realm local
                  path users.json
                }
                authentication portal myportal {
                  cookie domain localhost
                  enable identity store localdb
                }
              }
            }
            http://localhost:8080 {
              respond "Hello"
            }
            EOF
            ${caddy-security}/bin/caddy validate --adapter caddyfile --config Caddyfile
            touch $out
          '';

          test-l4 = pkgs.runCommand "test-l4" { } ''
            ${caddy-l4}/bin/caddy list-modules | grep "layer4"
            touch $out
          '';

          test-cache = pkgs.runCommand "test-cache" { } ''
            ${caddy-cache}/bin/caddy list-modules | grep "http.handlers.cache"
            cat <<'EOF' > Caddyfile
            http://localhost:8080 {
              cache {
                ttl 5m
              }
              respond "Hello"
            }
            EOF
            ${caddy-cache}/bin/caddy validate --adapter caddyfile --config Caddyfile
            touch $out
          '';

          test-waf = pkgs.runCommand "test-waf" { } ''
            ${caddy-waf}/bin/caddy list-modules | grep "http.handlers.waf"
            cat <<'EOF' > Caddyfile
            {
              order coraza_waf first
            }
            http://localhost:8080 {
              coraza_waf {
                directives `
                  SecRuleEngine On
                `
              }
              respond "Hello"
            }
            EOF
            ${caddy-waf}/bin/caddy validate --adapter caddyfile --config Caddyfile
            touch $out
          '';

          test-full = pkgs.runCommand "test-full" { } ''
            ${caddy-full}/bin/caddy list-modules | grep "dns.providers.cloudflare"
            ${caddy-full}/bin/caddy list-modules | grep "dns.providers.route53"
            ${caddy-full}/bin/caddy list-modules | grep "dns.providers.gandi"
            ${caddy-full}/bin/caddy list-modules | grep "dns.providers.digitalocean"
            ${caddy-full}/bin/caddy list-modules | grep "dns.providers.duckdns"
            ${caddy-full}/bin/caddy list-modules | grep "http.handlers.rate_limit"
            ${caddy-full}/bin/caddy list-modules | grep "dynamic_dns"
            ${caddy-full}/bin/caddy list-modules | grep "security"
            ${caddy-full}/bin/caddy list-modules | grep "layer4"
            ${caddy-full}/bin/caddy list-modules | grep "http.handlers.cache"
            ${caddy-full}/bin/caddy list-modules | grep "http.handlers.waf"
            touch $out
          '';

          # Check that all Nix files are formatted with nixpkgs-fmt
          nix-format = pkgs.runCommand "nix-format-check"
            {
              nativeBuildInputs = [ pkgs.nixpkgs-fmt ];
            } ''
            nixpkgs-fmt --check ${./flake.nix}
            touch $out
          '';
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nixpkgs-fmt
              pkgs.uv
            ];
          };
        }
      );
    };
}
