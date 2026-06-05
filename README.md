# Caddy Plugins Flake

A portable, self-updating Nix Flake providing custom Caddy builds with popular modules pre-installed. Supports macOS, Linux, and NixOS.

## NixOS Integration

To use this custom Caddy build in your NixOS configuration, add the flake to your inputs and set the `services.caddy.package` option.

Using `inputs.nixpkgs.follows` ensures Caddy is built using your system's `nixpkgs` revision to keep dependencies in sync.

### 1. Add to `flake.nix` Inputs

Choose the repository URL for your deployed version:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    caddy-plugins = {
      url = "github:seandlg/caddy-plugins-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, caddy-plugins, ... }@inputs: {
    # Pass inputs to NixOS configuration
  };
}
```

### 2. Configure Caddy Package & Select Variant

You can select which plugins you want by choosing the corresponding package variant:

- `packages.${system}.cloudflare`: Caddy + Cloudflare DNS
- `packages.${system}.route53`: Caddy + AWS Route53 DNS
- `packages.${system}.ratelimit`: Caddy + HTTP rate-limiting
- `packages.${system}.l4`: Caddy + Layer 4 routing
- `packages.${system}.full` (Default): Caddy + all of the above plugins bundled together

Example configuration in NixOS:

```nix
{ inputs, pkgs, ... }: {
  services.caddy = {
    enable = true;
    # Select your desired package variant (e.g. caddy with cloudflare DNS only)
    package = inputs.caddy-plugins.packages.${pkgs.system}.cloudflare;
    
    # Or use inputs.caddy-plugins.packages.${pkgs.system}.default for the full bundle
  };
}
```

---

## Local Development & Verification

### Using Native Nix (If Nix is installed)

Run the automated test suite locally:
```bash
# Run all native compilation and plugin checks
nix flake check -L

# Run caddy with a specific variant immediately
nix run .#cloudflare -- list-modules

# Build a specific package variant locally (creates ./result/bin/caddy)
nix build .#cloudflare
```

### Updating Plugin Hashes

If you add new plugins or want to bump plugin dependencies to their latest versions, you can run the parallel hash updater script. This script uses Python concurrently to calculate hashes for all variants:

```bash
# Calculate and update hashes.json
uv run update_hashes.py
```

---

## Inner Workings

- **Package Registry:** Hashes for each compilation variant are defined in `hashes.json` and read by `flake.nix` during build time.
- **Nix Checks:** Native Nix tests are defined in the `checks` output. Running `nix flake check` compiles all variants and executes assertions verifying the plugins are correctly built into each Caddy binary.
- **Nightly Automation:** A GitHub Action runs every night, updates `nixpkgs`, executes `uv run update_hashes.py` to fetch the latest plugin versions and recalculate hashes, and opens a Pull Request if changes exist.
