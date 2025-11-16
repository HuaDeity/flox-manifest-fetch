# Testing flox-manifest-fetch

This directory contains test configurations for the flox-manifest-fetch module, focusing on testing the authentication method priority order.

## Prerequisites

1. A Flox account with at least one environment
2. A Flox Hub token

## Configuration

Before running tests, edit `flake.nix` and update:

```nix
testUser = "flox";     # Replace with your Flox username
testEnv = "default";   # Replace with your environment name
```

## Authentication Method Priority

The module tests the following priority order:

1. **Direct token** (`token` option) - Highest priority
2. **Token file** (`tokenFile` option)
3. **Environment variable** (`FLOX_FLOXHUB_TOKEN`)
4. **Flox CLI** (`flox auth token` via `floxPackage`)
5. **Config file** (`~/.config/flox/flox.toml`) - Lowest priority

## Running Tests

### Setup

```bash
cd test
export FLOX_FLOXHUB_TOKEN="$(flox auth token)"
```

### Test 1: Direct Token (Priority 1)

Tests the highest priority method - direct token option.

```bash
nix build .#test-1-direct-token --impure
cat result/manifest.toml
cat result/generation
```

**Expected:** Fetches manifest using the token from `FLOX_FLOXHUB_TOKEN` env var passed to the `token` option.

### Test 2: Token File (Priority 2)

Tests the token file method.

```bash
nix build .#test-2-token-file --impure
cat result/manifest.toml
```

**Expected:** Fetches manifest using a token file created in the Nix store.

### Test 3: Environment Variable (Priority 3)

Tests falling back to the environment variable.

```bash
nix build .#test-3-env-var --impure
cat result/manifest.toml
```

**Expected:** Fetches manifest using `FLOX_FLOXHUB_TOKEN` when no higher priority methods are set.

### Test 4: Flox CLI from Flake (Priority 4)

Tests using the flox CLI from the flake input.

```bash
# Make sure you're logged in to flox
flox auth login

nix build .#test-4-flox-cli --impure
cat result/manifest.toml
```

**Expected:** Fetches manifest using `flox auth token` from the flox package in the flake input.

### Test 5: Priority Order

Tests that higher priority methods override lower priority ones.

```bash
nix build .#test-priority --impure
cat result/manifest.toml
```

**Expected:** Even though multiple auth methods are configured, the highest priority (direct token) is used.

### Test 6: Multiple Environments

Tests fetching manifests from multiple environments.

```bash
nix build .#test-multi-env --impure
ls -la result/
cat result/default.toml
```

**Expected:** Fetches manifests for both "default" and "development" environments (if they exist).

### Test 7: Run All Tests

Runs the complete test suite.

```bash
nix build .#test-all --impure
```

**Expected:** All tests pass and results are collected in the output directory.

## Development Shell

Enter a development environment with helpful commands:

```bash
cd test
nix develop
```

This will display all available test commands and usage instructions.

## Test Output

Each test produces:
- `manifest.toml` - The fetched Flox manifest
- `generation` - The generation number
- `test-name` - The name of the test that was run

## Understanding Test Results

### Success
```
=== Test 1: Direct Token (Priority 1) ===
Testing with: token option

SUCCESS: Manifest fetched using direct token
Generation: 23
```

### Failure
```
=== Test 1: Direct Token (Priority 1) ===
Testing with: token option

FAILED: Manifest not found
```

## Troubleshooting

### Error: "Could not resolve Flox token"

Make sure you've set `FLOX_FLOXHUB_TOKEN`:
```bash
export FLOX_FLOXHUB_TOKEN="$(flox auth token)"
```

### Error: "No generation directories found"

- Verify `testUser` matches your Flox username
- Verify `testEnv` exists in your Flox account
- Check your token has access to the environment

### Build hangs or is slow

The first build will:
1. Fetch the flox package from the flake input
2. Clone the floxmeta repository
3. Create cache for subsequent builds

Subsequent builds will be much faster.

## Module Evaluation

The tests use `lib.evalModules` to evaluate the floxManifests module directly:

```nix
evalModule = config:
  lib.evalModules {
    modules = [
      flox-manifest-fetch.nixosModules.default
      {
        _module.args = {
          inherit pkgs;
          floxPackage = flox-manifest-fetch.inputs.flox.packages.${system}.default;
        };
      }
      config
    ];
  };
```

This allows testing the module without using NixOS or home-manager.

## What Each Test Validates

| Test | Validates | Auth Method |
|------|-----------|-------------|
| test-1-direct-token | Highest priority | `token` option |
| test-2-token-file | Second priority | `tokenFile` option |
| test-3-env-var | Third priority | `FLOX_FLOXHUB_TOKEN` env var |
| test-4-flox-cli | Fourth priority | `floxPackage` with flox CLI |
| test-priority | Priority override | Multiple methods |
| test-multi-env | Multiple envs | Any method |
| test-all | Complete suite | All methods |

## Cleanup

Remove build artifacts:

```bash
cd test
rm -rf result result-*
nix-collect-garbage
```
