# Testing flox-manifest-fetch

This directory contains tests for the flox-manifest-fetch module.

## New Architecture

The module now uses a **two-step workflow**:

1. **Fetch**: Run the `fetch-manifests` script to download manifests to local cache
2. **Use**: Pure Nix module reads from the cache (no `--impure` needed!)

This separates the impure fetching step from the pure Nix evaluation, making the module much cleaner and more "Nix-like".

## Prerequisites

1. Update `test/flake.nix`:
   - Set `testUser` to your Flox username
   - Set `testEnv` to your environment name (e.g., "default")

2. Have a valid Flox token available via:
   - `FLOX_FLOXHUB_TOKEN` environment variable, or
   - `flox auth token` command, or
   - `~/.config/flox/flox.toml` config file

## Running Tests

### Step 1: Fetch manifests

From the root directory:

```bash
# Using command line arguments
nix run .#fetch-manifests -- --user YOUR_USER --envs default

# Or using environment variables
export FLOX_USER=YOUR_USER
export FLOX_ENVS=default
nix run .#fetch-manifests

# For multiple environments
nix run .#fetch-manifests -- --user YOUR_USER --envs default,development
```

This creates `.flox-manifests/` directory with cached manifests.

### Step 2: Run tests (Pure Nix!)

From the `test/` directory:

```bash
# Test 1: Basic manifest reading
nix build .#test-basic
cat result/manifest.toml

# Test 2: Multiple environments
nix build .#test-multi-env

# Run all tests
nix build .#test-all
```

**Notice**: No `--impure` flag needed! The module is now completely pure.

## Test Structure

### test-basic
Tests reading a single manifest from the cache. Verifies:
- Cache directory exists
- Manifest file is readable
- Generation number is present

### test-multi-env
Tests reading multiple environments. Demonstrates:
- Handling multiple environment names
- Fallback behavior when environments don't exist

### test-custom-cache
Tests using a custom cache directory:
```bash
# Fetch to custom location
FLOX_CACHE_DIR=/tmp/my-cache nix run ..#fetch-manifests -- --user USER --envs default

# Test reads from custom location
nix build .#test-custom-cache --impure
```

## Workflow Example

```bash
# 1. Clone repo
git clone https://github.com/youruser/flox-manifest-fetch
cd flox-manifest-fetch

# 2. Fetch manifests (one time or when they change)
nix run .#fetch-manifests -- --user myuser --envs default,development

# 3. Run tests (pure Nix, can run repeatedly)
cd test
nix build .#test-basic
nix build .#test-multi-env
nix build .#test-all

# 4. Check results
cat result/manifest.toml
cat result/generation
```

## Updating Manifests

When your Flox environments change:

```bash
# Re-run the fetch script
nix run .#fetch-manifests -- --user myuser --envs default

# Tests will now use updated manifests
cd test
nix build .#test-basic
```

## Integration Testing

To test the full workflow in your own configuration:

```nix
# flake.nix
{
  inputs.flox-manifest-fetch.url = "path:./path/to/flox-manifest-fetch";

  outputs = { self, nixpkgs, flox-manifest-fetch, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        flox-manifest-fetch.nixosModules.default
        {
          floxManifests = {
            enable = true;
            user = "myuser";
            environments = [ "default" ];
            cacheDir = ./flox-manifests;  # Point to your cache
          };

          # Use the manifests
          environment.etc."my-manifest.toml".source =
            config.floxManifests.manifests.default + "/manifest.toml";
        }
      ];
    };
  };
}
```

Then:
```bash
# Fetch manifests
nix run ./flox-manifest-fetch#fetch-manifests -- --user myuser --envs default

# Build system (pure!)
nixos-rebuild build --flake .#myhost
```

## Troubleshooting

### Error: "Manifest cache not found"

Run the fetch script first:
```bash
nix run ..#fetch-manifests -- --user YOUR_USER --envs ENV_NAME
```

### Error: "FLOX_USER is required"

Either:
- Use `--user` flag: `nix run .#fetch-manifests -- --user myuser --envs default`
- Or set environment variable: `export FLOX_USER=myuser`

### Cache location

Default cache: `.flox-manifests/` in the current directory

Check it exists:
```bash
ls -la .flox-manifests/
# Should show:
#   default/
#     manifest.toml
#     generation
```

### Starting fresh

Remove cache and re-fetch:
```bash
rm -rf .flox-manifests
nix run .#fetch-manifests -- --user myuser --envs default
```
