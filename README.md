# flox-manifest-fetch

A Nix module for fetching Flox environment manifests from FloxHub with a clean separation between fetching and usage.

## Features

- ✨ **Pure Nix evaluation** - No `--impure` flag required for builds
- 📦 **Two-step workflow** - Fetch once, use everywhere
- 🔐 **Flexible authentication** - Token file, env var, flox CLI, or config file
- 🏠 **NixOS & home-manager** - Works with both configuration systems
- 🔄 **Multi-environment** - Fetch manifests from multiple Flox environments
- 🎯 **Simple & clean** - Explicit control over when manifests update
- 📚 **Flox nixpkgs** - Uses `github:flox/nixpkgs/stable` for compatibility

## Architecture

This module uses a **two-step workflow** that separates impure operations from pure Nix evaluation:

1. **Fetch** (impure, run manually): `fetch-manifests` script downloads manifests to local cache
2. **Use** (pure, in Nix configs): Module reads manifests from cache directory

This approach:
- Eliminates the need for `--impure` in your system rebuilds
- Gives you explicit control over when manifests update
- Works perfectly with pure Nix evaluation
- Follows Nix best practices

## Quick Start

### Step 1: Add to your flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flox-manifest-fetch.url = "github:yourusername/flox-manifest-fetch";
  };

  outputs = { self, nixpkgs, flox-manifest-fetch, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        flox-manifest-fetch.nixosModules.default
        {
          floxManifests = {
            enable = true;
            user = "myusername";
            environments = [ "default" ];
            cacheDir = ./flox-manifests;  # Point to local cache
          };

          # Use the manifests
          environment.etc."my-flox-manifest.toml".source =
            config.floxManifests.manifests.default + "/manifest.toml";
        }
      ];
    };
  };
}
```

### Step 2: Fetch manifests

```bash
# From your project directory
nix run github:yourusername/flox-manifest-fetch#fetch-manifests -- \
  --user myusername \
  --envs default

# This creates ./flox-manifests/ with your manifests
```

### Step 3: Build your system (pure!)

```bash
nixos-rebuild switch --flake .#myhost
# No --impure flag needed!
```

## Configuration Options

### `floxManifests.enable`
- **Type**: `boolean`
- **Default**: `false`
- **Description**: Enable Flox manifest management

### `floxManifests.user`
- **Type**: `string`
- **Required**: Yes
- **Example**: `"myusername"`
- **Description**: Flox username for accessing FloxHub

### `floxManifests.environments`
- **Type**: `list of strings`
- **Default**: `[]`
- **Example**: `[ "default" "development" "production" ]`
- **Description**: List of Flox environments to load manifests for

### `floxManifests.cacheDir`
- **Type**: `path`
- **Default**: `./.flox-manifests`
- **Example**: `./flox-manifests` or `/etc/flox-manifests`
- **Description**: Directory where `fetch-manifests` stores cached manifests

### `floxManifests.manifests`
- **Type**: `attribute set of packages` (read-only)
- **Description**: Derivations containing manifest.toml files, keyed by environment name

### `floxManifests.outputPath`
- **Type**: `null or path`
- **Default**: `null`
- **Example**: `"/etc/flox/manifests"`
- **Description**: Optional path to copy all manifests to (NixOS only)

## Usage

### Fetching Manifests

The `fetch-manifests` script downloads manifests from FloxHub to a local cache directory.

#### Using command-line arguments:

```bash
nix run .#fetch-manifests -- --user myuser --envs default,development
```

#### Using environment variables:

```bash
export FLOX_USER=myuser
export FLOX_ENVS=default,development
nix run .#fetch-manifests
```

#### Custom cache directory:

```bash
nix run .#fetch-manifests -- \
  --user myuser \
  --envs default \
  --cache-dir /etc/flox-manifests
```

#### Options:

- `--user USER` - Flox username (required)
- `--envs ENV1,ENV2` - Comma-separated list of environments (required)
- `--cache-dir DIR` - Cache directory (default: `.flox-manifests`)
- `--token TOKEN` - FloxHub token (optional, see authentication below)
- `--help` - Show help message

### Authentication

The fetch script tries these methods in order:

1. `--token` command-line argument
2. `FLOX_FLOXHUB_TOKEN` environment variable
3. `flox auth token` command (if flox is available)
4. `~/.config/flox/flox.toml` config file

Example:

```bash
# Using environment variable
export FLOX_FLOXHUB_TOKEN="$(flox auth token)"
nix run .#fetch-manifests -- --user myuser --envs default

# Using flox CLI (automatic)
flox auth login
nix run .#fetch-manifests -- --user myuser --envs default
```

### Using Manifests in NixOS

```nix
{ config, ... }:

{
  imports = [ flox-manifest-fetch.nixosModules.default ];

  floxManifests = {
    enable = true;
    user = "myusername";
    environments = [ "default" "production" ];
    cacheDir = ./flox-manifests;
  };

  # Copy manifest to /etc
  environment.etc."flox-default.toml".source =
    config.floxManifests.manifests.default + "/manifest.toml";

  # Read generation number
  environment.sessionVariables.FLOX_GEN =
    builtins.readFile (config.floxManifests.manifests.default + "/generation");
}
```

### Using Manifests in home-manager

```nix
{ config, ... }:

{
  imports = [ flox-manifest-fetch.homeManagerModules.default ];

  floxManifests = {
    enable = true;
    user = "myusername";
    environments = [ "default" ];
    cacheDir = ./flox-manifests;
  };

  # Copy manifest to home directory
  home.file."my-manifest.toml".source =
    config.floxManifests.manifests.default + "/manifest.toml";

  # Parse and use manifest content
  home.sessionVariables =
    let
      manifest = pkgs.lib.importTOML
        (config.floxManifests.manifests.default + "/manifest.toml");
    in {
      FLOX_ENV_NAME = manifest.hook.on-activate or "default";
    };
}
```

## Cache Directory Structure

After running `fetch-manifests`, your cache directory will look like:

```
.flox-manifests/
├── default/
│   ├── manifest.toml     # The manifest file
│   └── generation        # Generation number
├── development/
│   ├── manifest.toml
│   └── generation
└── production/
    ├── manifest.toml
    └── generation
```

You can:
- **Commit to git**: Share manifests with your team
- **Add to .gitignore**: Fetch fresh each time
- **Mix both**: Commit stable envs, gitignore experimental ones

## Workflow Examples

### Daily Development

```bash
# Morning: Update manifests if needed
nix run .#fetch-manifests -- --user myuser --envs default

# Use throughout the day (pure builds)
nixos-rebuild switch
home-manager switch
nix build .#mypackage
```

### CI/CD

```yaml
# .github/workflows/build.yml
steps:
  - name: Fetch Flox manifests
    run: |
      nix run .#fetch-manifests -- \
        --user ${{ secrets.FLOX_USER }} \
        --envs default \
        --token ${{ secrets.FLOX_TOKEN }}

  - name: Build system (pure)
    run: nixos-rebuild build --flake .#myhost
```

### Git Hooks

```bash
# .git/hooks/post-merge
#!/usr/bin/env bash
# Auto-fetch manifests after pulling
nix run .#fetch-manifests -- --user myuser --envs default
```

### Multiple Users

```nix
{
  floxManifests = {
    enable = true;
    user = "team";
    environments = [ "shared-dev" "shared-prod" ];
    cacheDir = /etc/flox-team-manifests;
  };
}
```

Then fetch to system location:
```bash
sudo nix run .#fetch-manifests -- \
  --user team \
  --envs shared-dev,shared-prod \
  --cache-dir /etc/flox-team-manifests
```

## Updating Manifests

When your Flox environments change:

```bash
# Re-fetch manifests
nix run .#fetch-manifests -- --user myuser --envs default

# Rebuild to use updated manifests
nixos-rebuild switch
```

The module will automatically use the freshly fetched manifests.

## Secrets Management

### With sops-nix

```nix
{
  # Store token in encrypted secrets
  sops.secrets.flox-token = {
    sopsFile = ./secrets.yaml;
  };

  # Use in activation script to fetch manifests
  system.activationScripts.fetchFloxManifests = ''
    export FLOX_FLOXHUB_TOKEN=$(cat ${config.sops.secrets.flox-token.path})
    ${pkgs.flox-manifest-fetch}/bin/fetch-manifests \
      --user myuser \
      --envs default \
      --cache-dir /var/lib/flox-manifests
  '';

  floxManifests = {
    enable = true;
    user = "myuser";
    environments = [ "default" ];
    cacheDir = /var/lib/flox-manifests;
  };
}
```

### With agenix

Similar approach using age-encrypted secrets.

## Development

### Running Tests

```bash
# Fetch test manifests
nix run .#fetch-manifests -- --user flox --envs default

# Run tests (pure!)
cd test
nix build .#test-basic
nix build .#test-multi-env
nix build .#test-all
```

See [test/README.md](test/README.md) for detailed testing documentation.

### Development Shell

```bash
nix develop
# or
nix develop ./test
```

## Troubleshooting

### Error: "Manifest cache not found for environment 'default'"

Run the fetch script first:
```bash
nix run .#fetch-manifests -- --user YOUR_USER --envs default
```

### Error: "FLOX_USER is required"

The fetch script needs to know your Flox username:
```bash
nix run .#fetch-manifests -- --user myuser --envs default
```

### Manifests not updating

Re-run the fetch script:
```bash
nix run .#fetch-manifests -- --user myuser --envs default
```

### Cache directory location

The module looks for manifests in `cacheDir`:
```nix
floxManifests.cacheDir = ./flox-manifests;  # Relative to flake
floxManifests.cacheDir = /etc/flox-manifests;  # Absolute path
```

Ensure the fetch script writes to the same location:
```bash
nix run .#fetch-manifests -- \
  --cache-dir ./flox-manifests \
  --user myuser \
  --envs default
```

## How It Works

1. **Fetching (impure)**:
   - `fetch-manifests` script clones floxmeta repo from FloxHub
   - Finds latest generation (highest numbered directory)
   - Extracts `manifest.toml` to local cache
   - All impure operations happen here

2. **Using (pure)**:
   - Nix module reads from local cache using `builtins.pathExists`
   - Creates derivations that copy manifests to Nix store
   - No network access, no impure evaluation
   - Fast and deterministic

## Comparison with Previous Approaches

| Approach | Pure Eval | Network at Build | Caching | User Control |
|----------|-----------|------------------|---------|--------------|
| builtins.fetchGit | ❌ No | ✅ Yes | ✅ Yes | ❌ No |
| FOD | ✅ Yes | ✅ Yes | ⚠️ Flaky | ❌ No |
| __impure flag | ❌ No | ✅ Yes | ❌ No | ❌ No |
| **Two-step (this)** | ✅ Yes | ❌ No | ✅ Yes | ✅ Yes |

## License

MIT

## Contributing

Contributions welcome! Please open an issue or PR.
