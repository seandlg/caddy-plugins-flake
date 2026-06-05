import json
import subprocess
import re
import sys
import os
import shutil
from concurrent.futures import ThreadPoolExecutor, as_completed

# Ensure Nix binaries are in PATH
nix_paths = [
    "/nix/var/nix/profiles/default/bin",
    "/run/current-system/sw/bin",
    os.path.expanduser("~/.nix-profile/bin")
]
current_path = os.environ.get("PATH", "")
for p in nix_paths:
    if p not in current_path:
        current_path = f"{p}:{current_path}"
os.environ["PATH"] = current_path

PACKAGES = [
    "cloudflare", "route53", "gandi", "digitalocean", "duckdns",
    "ratelimit", "dynamicdns", "security", "l4", "cache", "waf", "full"
]

def calculate_hash(pkg):
    print(f"-> Starting build for '{pkg}'...", flush=True)
    cmd = ["nix", "--extra-experimental-features", "nix-command flakes", "build", f".#{pkg}", "--no-link", "-L"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=1200)
        output = result.stdout + "\n" + result.stderr
    except subprocess.TimeoutExpired:
        print(f"✗ Error: Build for '{pkg}' timed out after 20 minutes.", flush=True)
        return pkg, None
    
    # Search for "got: sha256-..."
    match = re.search(r"got:\s+(sha256-[A-Za-z0-9+/=]+)", output)
    if not match:
        match = re.search(r"specified:\s+sha256-[^\n]+\n\s+got:\s+(sha256-[A-Za-z0-9+/=]+)", output)
        if not match:
            match = re.search(r"specified:\s+sha256-[^\n]+\n\s+(sha256-[A-Za-z0-9+/=]+)", output)
            
    if match:
        new_hash = match.group(1)
        print(f"✓ Found hash for '{pkg}': {new_hash}", flush=True)
        return pkg, new_hash
    else:
        print(f"✗ Error: Failed to find hash for '{pkg}'. Output:\n{output}", flush=True)
        return pkg, None

def main():
    # Verify nix is available
    if not shutil.which("nix"):
        print("✗ Error: 'nix' executable not found in PATH.", flush=True)
        print("Please ensure Nix is installed and active on your system.", flush=True)
        sys.exit(1)

    # 1. Reset all hashes in hashes.json to dummy hashes
    try:
        with open('hashes.json', 'r') as f:
            hashes = json.load(f)
    except FileNotFoundError:
        hashes = {}

    for pkg in PACKAGES:
        hashes[pkg] = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        
    with open('hashes.json', 'w') as f:
        json.dump(hashes, f, indent=2)

    # Stage changes in Git so Nix Flakes can see the reset hashes
    subprocess.run(["git", "add", "hashes.json"])

    print("Running Nix builds in parallel...", flush=True)
    results = {}
    
    # 2. Run builds concurrently using a thread pool
    with ThreadPoolExecutor(max_workers=len(PACKAGES)) as executor:
        futures = {executor.submit(calculate_hash, pkg): pkg for pkg in PACKAGES}
        completed = 0
        for future in as_completed(futures):
            pkg, new_hash = future.result()
            if new_hash is None:
                sys.exit(1)
            results[pkg] = new_hash
            completed += 1
            print(f"Progress: [{completed}/{len(PACKAGES)}] completed build for '{pkg}'", flush=True)

    # 3. Write all correct hashes back to hashes.json
    for pkg, new_hash in results.items():
        hashes[pkg] = new_hash

    with open('hashes.json', 'w') as f:
        json.dump(hashes, f, indent=2)

    # Stage the final hashes.json
    subprocess.run(["git", "add", "hashes.json"])
    print("✓ Successfully populated hashes.json with correct plugin hashes!", flush=True)

if __name__ == '__main__':
    main()
