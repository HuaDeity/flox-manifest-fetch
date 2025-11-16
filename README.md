# flox-manifest-fetch

Fetch Flox manifests from FloxHub and use them in your Nix configurations.

## Features

- ✨ **Pure Nix evaluation** - No `--impure` flag needed
- 📦 **Two-step workflow** - Fetch once, use everywhere
- 🔐 **Simple auth** - Uses `flox auth token`
- 🔄 **Multi-environment** - Fetch multiple environments at once
- 🎯 **Explicit control** - You decide when to update

## Quick Start

### 1. Add to your flake

```nix
{
  inputs.flox-manifest-fetch.url = "github:HuaDeity/flox-manifest-fetch";

  outputs = { self, flox-manifest-fetch, ... }: {
    # Darwin example
    darwinConfigurations.myhost = darwin.lib.darwinSystem {
      modules = [
        flox-manifest-fetch.flakeModules.floxManifests
        {
          floxManifests = {
            enable = true;
            environments = [ "default" ];
            cacheDir = ".flox-manifests";
          };
        }
      ];
    };
  };
}
```

### 2. Copy the justfile (recommended)

```bash
# Copy the justfile template to your config repo
cp path/to/flox-manifest-fetch/justfile .
```

### 3. One-command workflow

```bash
# Login to flox (first time only)
flox auth login

# Update: fetch manifests + rebuild (auto-detects everything!)
just update
```

**That's it!** The `just update` command will:

- Auto-detect your hostname
- Extract environments and cache-dir from your Nix config
- Fetch the latest Flox manifests
- Rebuild your system

### Alternative: Manual workflow

```bash
# Fetch manifests (username auto-detected)
nix run github:yourusername/flox-manifest-fetch#fetch-manifests -- \
  --envs default

# Build (pure!)
nixos-rebuild switch
```

## How It Works

### Two-Step Workflow

**Step 1: Fetch (manual)**

```bash
nix run .#fetch-manifests -- --user YOU --envs default
```

- Runs outside Nix evaluation
- Fetches latest manifests from FloxHub
- Stores in local cache directory

**Step 2: Use (automatic)**

```nix
floxManifests.manifests  # List of cache paths
```

- Module reads from cache
- Pure Nix evaluation
- No network access

## Module Options

### `floxManifests.enable`

- Type: `boolean`
- Default: `false`

### `floxManifests.environments`

- Type: `list of strings`
- Default: `[]`
- Example: `[ "default" "development" ]`
- Environment names to load

### `floxManifests.cacheDir`

- Type: `string`
- Default: `".flox-manifests"`
- Example: `"/etc/flox-manifests"`
- Cache directory path

### `floxManifests.manifests` (read-only)

- Type: `list of strings`
- List of paths to cached manifest directories
- Example: `[ ".flox-manifests/default" ".flox-manifests/development" ]`

## fetch-manifests Script

### Usage

```bash
nix run .#fetch-manifests -- [OPTIONS]
```

### Options

- `--user USER` - Flox username (optional, auto-detected from `flox auth status`)
- `--envs ENV1,ENV2` - Comma-separated environments (required, or set `FLOX_ENVS`)
- `--cache-dir DIR` - Cache directory (default: `.flox-manifests`)
- `--help` - Show help

### Authentication

Automatically uses:

- Username from `flox auth status`
- Token from `flox auth token`

Run `flox auth login` first.

## Justfile Integration

The included justfile provides a complete rebuild workflow with automatic manifest fetching.

### Quick Start

```bash
# Interactive menu
just

# Update: fetch manifests + rebuild (auto-detects hostname)
just update

# Update home-manager
just update-home

# Show current configuration
just show
```

### Main Commands

**`just update`** - Fetch manifests and rebuild system

- Auto-detects hostname from `hostname -s`
- Extracts config from `.#darwinConfigurations.{hostname}` (macOS) or `.#nixosConfigurations.{hostname}` (Linux)
- Fetches Flox manifests if enabled
- Runs `just switch` to rebuild

**`just update-home [user]`** - Update home-manager

- Defaults to current user
- Extracts config from `.#homeConfigurations."{user}@{hostname}"`
- Fetches manifests and runs `home-manager switch`

**`just show`** - Show Flox manifests configuration

- Displays enabled status, environments, and cache directory

### Standard Commands

All standard rebuild commands work as expected:

- `just build` - Build system configuration
- `just switch` - Switch to new configuration (with confirmation)
- `just check` - Check configuration
- `just boot` - Set configuration for next boot (Linux only)
- `just home switch` - Switch home-manager configuration
- `just clean` - Clean old generations and optimize store

### How It Works

The `update` command automatically:

1. Detects your hostname
2. Checks if `floxManifests.enable = true` in your config
3. Extracts environments and cache directory from your config
4. Runs `fetch-manifests` with those values
5. Continues with normal rebuild

If `floxManifests` is not enabled, it skips the fetch step gracefully.

## Examples

### Basic Usage

```nix
{
  imports = [ flox-manifest-fetch.flakeModules.floxManifests ];

  floxManifests = {
    enable = true;
    environments = [ "default" ];
  };

  # Use the manifest
  environment.etc."my-manifest.toml".source =
    "${builtins.head config.floxManifests.manifests}/manifest.toml";
}
```

### Multiple Environments

```nix
{
  floxManifests = {
    enable = true;
    environments = [ "default" "development" "production" ];
  };

  # Copy all manifests to /etc
  environment.etc = lib.listToAttrs (
    map (manifestPath:
      let envName = builtins.baseNameOf manifestPath; in
      lib.nameValuePair "flox/${envName}.toml" {
        source = "${manifestPath}/manifest.toml";
      }
    ) config.floxManifests.manifests
  );
}
```

### Read Generation Number

```nix
{
  environment.sessionVariables.FLOX_GEN = builtins.readFile
    "${builtins.head config.floxManifests.manifests}/generation";
}
```

### Parse Manifest TOML

```nix
{
  home.sessionVariables =
    let
      manifestPath = builtins.head config.floxManifests.manifests;
      manifest = lib.importTOML "${manifestPath}/manifest.toml";
    in {
      MY_VAR = manifest.someField or "default";
    };
}
```

### home-manager

```nix
{
  imports = [ flox-manifest-fetch.flakeModules.floxManifests ];

  floxManifests = {
    enable = true;
    environments = [ "default" ];
  };

  home.file."my-manifest.toml".source =
    "${builtins.head config.floxManifests.manifests}/manifest.toml";
}
```

## Workflows

### Daily Development

**Recommended workflow with justfile:**

```bash
# One command to fetch manifests and rebuild
just update
```

**Manual workflow:**

```bash
# Fetch manifests
nix run .#fetch-manifests -- --envs default

# Build (pure)
nixos-rebuild switch --flake .
```

### CI/CD

**With justfile:**

```yaml
steps:
  - name: Setup
    run: |
      nix profile install nixpkgs#just
      flox auth login

  - name: Update system
    run: just update
```

**Manual:**

```yaml
steps:
  - name: Fetch and build
    run: |
      flox auth login
      nix run .#fetch-manifests -- --envs default
      nixos-rebuild build --flake .#myhost
```

### Git: Commit Manifests

**With justfile:**

```bash
# Update includes fetch
just update

# Commit the fetched manifests
git add .flox-manifests
git commit -m "Update manifests"

# Team gets manifests automatically
git pull
just update
```

**Manual:**

```bash
# Fetch and commit
nix run .#fetch-manifests -- --envs default
git add .flox-manifests
git commit -m "Update manifests"

# Team gets manifests automatically
git pull
nixos-rebuild switch
```

### Git: Ignore Manifests

```gitignore
# .gitignore
.flox-manifests/
```

**With justfile:**

```bash
# Each developer runs update (fetches automatically)
just update
```

**Manual:**

```bash
# Each developer fetches locally
nix run .#fetch-manifests -- --envs default
```

## Cache Structure

```
.flox-manifests/
├── default/
│   ├── manifest.toml
│   └── generation
└── development/
    ├── manifest.toml
    └── generation
```

## Troubleshooting

### "Error: Failed to get token"

```bash
flox auth login
```

### "Cache not found"

```bash
nix run .#fetch-manifests -- --envs default
```

### "Could not detect username"

Make sure you're logged in:

```bash
flox auth login
flox auth status  # Should show: "You are logged in as USERNAME..."
```

Or provide username manually:

```bash
nix run .#fetch-manifests -- --user USERNAME --envs default
```

### "Wrong cache directory"

Make sure cacheDir matches:

```nix
floxManifests.cacheDir = "/etc/flox";
```

```bash
nix run .#fetch-manifests -- --cache-dir /etc/flox --envs default
```

## Why Two Steps?

### Without Separation

- Network access during eval → requires `--impure`
- No control over updates → surprise rebuilds
- Slow, unreliable evaluation

### With Separation

- Explicit fetch step → you control when
- Pure evaluation → fast and deterministic
- Works offline after fetch → reliable

## License

MIT
