#!/usr/bin/env bash
set -e

PACKAGES=("cloudflare" "route53" "ratelimit" "l4" "full")

# Helper to run sed in-place compatibly on macOS and Linux
run_sed() {
  local pattern="$1"
  local file="$2"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$pattern" "$file"
  else
    sed -i "$pattern" "$file"
  fi
}

# 1. Reset all hashes to dummy hashes in hashes.json
for pkg in "${PACKAGES[@]}"; do
  run_sed "s/\"$pkg\": \"[^\"]*\"/\"$pkg\": \"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\"/g" hashes.json
done

# 2. Stage changes so Nix Flakes can see the updated hashes.json
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add hashes.json
fi

# 3. Build each package to fetch and extract the correct hash
for pkg in "${PACKAGES[@]}"; do
  echo "Calculating hash for package '$pkg'..."
  TEMP_LOG=$(mktemp)

  # Check if Nix is installed natively on this host
  if command -v nix >/dev/null 2>&1; then
    # Run native nix build (e.g. in GitHub Actions)
    nix --extra-experimental-features "nix-command flakes" build .#"$pkg" --no-link -L > "$TEMP_LOG" 2>&1 || true
  else
    # Fall back to Docker (local Mac development)
    docker run --rm \
      -v nix-store-cache:/nix \
      -v "$(pwd)":/workspace \
      -w /workspace \
      nixos/nix:latest \
      nix --extra-experimental-features "nix-command flakes" build .#"$pkg" --no-link -L > "$TEMP_LOG" 2>&1 || true
  fi

  # Extract the correct hash from the Nix mismatch output
  NEW_HASH=$(grep -A 1 "specified:" "$TEMP_LOG" | tail -n 1 | awk '{print $NF}' || true)
  if [ -z "$NEW_HASH" ]; then
    NEW_HASH=$(grep "got:" "$TEMP_LOG" | awk '{print $2}' || true)
  fi

  # Verify we actually got a valid sha256 hash
  if [ -n "$NEW_HASH" ] && [[ "$NEW_HASH" == sha256-* ]]; then
    echo "Found hash for '$pkg': $NEW_HASH"
    run_sed "s/\"$pkg\": \"[^\"]*\"/\"$pkg\": \"$NEW_HASH\"/g" hashes.json
  else
    echo "Error: Could not calculate hash for package '$pkg'. Build output:"
    cat "$TEMP_LOG"
    rm -f "$TEMP_LOG"
    exit 1
  fi

  rm -f "$TEMP_LOG"

  # Stage hashes.json again so the next loop run uses the updated hashes
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git add hashes.json
  fi
done

echo "Successfully populated hashes.json with correct plugin hashes!"
