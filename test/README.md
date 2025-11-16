# Testing flox-manifest-fetch

This directory contains test configurations for the flox-manifest-fetch module.

## Prerequisites

1. A Flox account with at least one environment
2. A Flox Hub token (get it via `flox auth token` or from `~/.config/flox/flox.toml`)

## Configuration

Before running tests, edit `flake.nix` and replace:
- `user = "flox"` with your actual Flox username

## Running Tests

### Test 1: Standalone Manifest Fetch

Fetch a manifest without using the full module:

```bash
cd test
export FLOX_FLOXHUB_TOKEN="your-token-here"
nix build .#test-manifest --impure
cat result/manifest.toml
cat result/generation
```

**Expected output:**
- `result/manifest.toml`: Your Flox environment manifest
- `result/generation`: The generation number (e.g., "23")

### Test 2: Home-Manager Integration

Test the module in a home-manager configuration:

```bash
cd test
export FLOX_FLOXHUB_TOKEN="your-token-here"
nix build .#homeConfigurations.testuser.activationPackage --impure
```

**Expected output:**
- Successful build of home-manager activation package
- Module correctly fetches and integrates manifests

### Test 3: Module Load Check

Verify the module can be imported without errors:

```bash
cd test
nix build .#checks.x86_64-linux.module-loads
```

**Expected output:**
- Successful build confirming module loads correctly

## Development Shell

Enter a development environment with helpful commands:

```bash
cd test
nix develop
```

This will display all available test commands.

## Testing Different Token Sources

### Using Direct Token (Not Recommended - Testing Only)

Edit `flake.nix`:
```nix
floxManifests = {
  enable = true;
  user = "your-username";
  environments = [ "default" ];
  token = "your-token-here";  # Visible in nix store!
};
```

Build without `--impure`:
```bash
nix build .#homeConfigurations.testuser.activationPackage
```

### Using Token File (Recommended)

Create a token file:
```bash
echo "your-token" > /tmp/flox-token
chmod 600 /tmp/flox-token
```

Edit `flake.nix`:
```nix
floxManifests = {
  enable = true;
  user = "your-username";
  environments = [ "default" ];
  tokenFile = /tmp/flox-token;
};
```

Build without `--impure`:
```bash
nix build .#homeConfigurations.testuser.activationPackage
```

### Using Environment Variable (Impure)

```bash
export FLOX_FLOXHUB_TOKEN="your-token"
nix build .#homeConfigurations.testuser.activationPackage --impure
```

### Using Flox CLI (Impure)

Make sure you're logged in to Flox:
```bash
flox auth login
```

Build with `--impure`:
```bash
nix build .#homeConfigurations.testuser.activationPackage --impure
```

The module will automatically use `flox auth token` from the flake input.

### Using Config File (Impure)

Ensure `~/.config/flox/flox.toml` exists with:
```toml
floxhub_token = "your-token-here"
```

Build with `--impure`:
```bash
nix build .#homeConfigurations.testuser.activationPackage --impure
```

## Testing Multiple Environments

Edit `flake.nix`:
```nix
floxManifests = {
  enable = true;
  user = "your-username";
  environments = [ "default" "development" "production" ];
  tokenFile = /tmp/flox-token;
};
```

Access different manifests:
```nix
home.file."default.toml".source = "${config.floxManifests.manifests.default}/manifest.toml";
home.file."dev.toml".source = "${config.floxManifests.manifests.development}/manifest.toml";
home.file."prod.toml".source = "${config.floxManifests.manifests.production}/manifest.toml";
```

## Troubleshooting

### Error: "Could not resolve Flox token"

Make sure you've set at least one token source (see above).

### Error: "No generation directories found"

- Check that the environment name exists in your Flox account
- Verify your token has access to the environment
- Ensure the username is correct

### Error: "Manifest not found at..."

The environment exists but doesn't have a valid manifest. Check your Flox environment.

### Build hangs or is slow

The first build will:
1. Fetch the flox package (if using CLI fallback)
2. Clone the floxmeta repository
3. Cache is created for subsequent builds

## Cleanup

Remove build artifacts:
```bash
cd test
rm -rf result result-*
nix-collect-garbage
```
