{
  description = "A portable, customizable Caddy binary with popular plugins built in";

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
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          # Caddy with Cloudflare DNS plugin (for DNS-01 ACME challenges)
          cloudflare = buildCaddy pkgs [ "github.com/caddy-dns/cloudflare@latest" ] hashes.cloudflare;

          # Caddy with AWS Route53 DNS plugin (for DNS-01 ACME challenges)
          route53 = buildCaddy pkgs [ "github.com/caddy-dns/route53@latest" ] hashes.route53;

          # Caddy with HTTP rate-limiting plugin
          ratelimit = buildCaddy pkgs [ "github.com/mholt/caddy-ratelimit@latest" ] hashes.ratelimit;

          # Caddy with Layer 4 routing support
          l4 = buildCaddy pkgs [ "github.com/mholt/caddy-l4@latest" ] hashes.l4;

          # Caddy with ALL of the above plugins bundled together
          full = buildCaddy pkgs [
            "github.com/caddy-dns/cloudflare@latest"
            "github.com/caddy-dns/route53@latest"
            "github.com/mholt/caddy-ratelimit@latest"
            "github.com/mholt/caddy-l4@latest"
          ]
            hashes.full;

          default = full;
        }
      );

      # Native Nix test checks to verify compilation and plugins are present
      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          caddy-cloudflare = self.packages.${system}.cloudflare;
          caddy-route53 = self.packages.${system}.route53;
          caddy-ratelimit = self.packages.${system}.ratelimit;
          caddy-l4 = self.packages.${system}.l4;
          caddy-full = self.packages.${system}.full;
        in
        {
          test-cloudflare = pkgs.runCommand "test-cloudflare" { } ''
            ${caddy-cloudflare}/bin/caddy list-modules | grep "dns.providers.cloudflare"
            touch $out
          '';
          test-route53 = pkgs.runCommand "test-route53" { } ''
            ${caddy-route53}/bin/caddy list-modules | grep "dns.providers.route53"
            touch $out
          '';
          test-ratelimit = pkgs.runCommand "test-ratelimit" { } ''
            ${caddy-ratelimit}/bin/caddy list-modules | grep "http.handlers.rate_limit"
            touch $out
          '';
          test-l4 = pkgs.runCommand "test-l4" { } ''
            ${caddy-l4}/bin/caddy list-modules | grep "layer4"
            touch $out
          '';
          test-full = pkgs.runCommand "test-full" { } ''
            ${caddy-full}/bin/caddy list-modules | grep "dns.providers.cloudflare"
            ${caddy-full}/bin/caddy list-modules | grep "dns.providers.route53"
            ${caddy-full}/bin/caddy list-modules | grep "http.handlers.rate_limit"
            ${caddy-full}/bin/caddy list-modules | grep "layer4"
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

          # Check that our bash script is linted with shellcheck
          shell-lint = pkgs.runCommand "shell-lint-check"
            {
              nativeBuildInputs = [ pkgs.shellcheck ];
            } ''
            shellcheck ${./update_hashes.sh}
            touch $out
          '';
        }
      );
    };
}
