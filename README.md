# flox-manifest-fetch

A Nix module for fetching Flox environment manifests from FloxHub. This module integrates with NixOS and home-manager to automatically fetch and manage Flox `manifest.toml` files.

## Features

- 🔐 **Multiple token sources**: Direct token, token file, environment variables, Flox CLI, or config file
- ✨ **Pure by default**: Use token or tokenFile for pure Nix evaluation
- 🔄 **Automatic fallback**: Tries multiple token sources in order
- 📦 **Multi-environment**: Fetch manifests from multiple Flox environments
- 🏠 **Home-manager & NixOS**: Works with both configuration systems
- 🔒 **Secrets-friendly**: Integrates with sops-nix, agenix, etc.

## Quick Start

### Add to your flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flox-manifest-fetch.url = "github:yourusername/flox-manifest-fetch";
  };

  outputs = { self, nixpkgs, flox-manifest-fetch, ... }: {
    # NixOS configuration
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        flox-manifest-fetch.nixosModules.default
        {
          floxManifests = {
            enable = true;
            user = "myusername";
            environments = [ "default" ];
            tokenFile = /run/secrets/flox-token;
          };
        }
      ];
    };

    # home-manager configuration
    homeConfigurations.myuser = home-manager.lib.homeManagerConfiguration {
      modules = [
        flox-manifest-fetch.homeManagerModules.default
        {
          floxManifests = {
            enable = true;
            user = "myusername";
            environments = [ "default" ];
            tokenFile = /run/secrets/flox-token;
          };
        }
      ];
    };
  };
}
```

## Configuration Options

### `floxManifests.enable`
- **Type**: `boolean`
- **Default**: `false`
- **Description**: Enable the Flox manifest fetcher

### `floxManifests.user`
- **Type**: `string`
- **Required**: Yes
- **Example**: `"myusername"`
- **Description**: Flox owner/username for the floxmeta repository

### `floxManifests.environments`
- **Type**: `list of strings`
- **Default**: `[ "default" ]`
- **Example**: `[ "default" "development" "production" ]`
- **Description**: List of environment names (git branches) to fetch manifests from

### `floxManifests.token`
- **Type**: `null or string`
- **Default**: `null`
- **Description**: Flox Hub token (highest priority, but visible in Nix store)

### `floxManifests.tokenFile`
- **Type**: `null or path`
- **Default**: `null`
- **Example**: `"/run/secrets/flox-token"`
- **Description**: Path to file containing Flox Hub token (recommended for secrets)

### `floxManifests.floxBin`
- **Type**: `string`
- **Default**: `"flox"`
- **Example**: `"/home/user/.nix-profile/bin/flox"`
- **Description**: Flox binary path or name (used in fallback chain)

### `floxManifests.manifests` (read-only)
- **Type**: `attribute set of derivations`
- **Description**: Output containing derivations with manifest.toml files

## Token Resolution

The module tries the following sources in order:

1. **`token` option** (Pure) - Direct token value
2. **`tokenFile` option** (Pure) - Read from file
3. **`FLOX_FLOXHUB_TOKEN` env var** (Impure) - Requires `--impure` flag
4. **`flox auth token` CLI** (Impure) - Requires `--impure` and flox installed
5. **`~/.config/flox/flox.toml`** (Impure) - Requires `--impure`

### Pure vs Impure

**Pure evaluation** (options 1-2):
```bash
nixos-rebuild switch
home-manager switch
```

**Impure evaluation** (options 3-5):
```bash
nixos-rebuild switch --impure
home-manager switch --impure
```

## Usage Examples

### Home Manager

```nix
{ config, ... }:
{
  floxManifests = {
    enable = true;
    user = "myusername";
    environments = [ "default" "development" ];
    tokenFile = /run/secrets/flox-token;
  };

  # Copy manifest to home directory
  home.file."my-manifest.toml".source =
    "${config.floxManifests.manifests.default}/manifest.toml";

  # Use manifest generation number
  home.sessionVariables.FLOX_GEN =
    builtins.readFile "${config.floxManifests.manifests.default}/generation";
}
```

### NixOS

```nix
{ config, pkgs, lib, ... }:
{
  floxManifests = {
    enable = true;
    user = "myorganization";
    environments = [ "production" ];
    tokenFile = "/run/secrets/flox-token";
  };

  # Create system file
  environment.etc."flox/manifest.toml".source =
    "${config.floxManifests.manifests.production}/manifest.toml";

  # Parse and use manifest
  environment.systemPackages =
    let
      manifest = lib.importTOML
        "${config.floxManifests.manifests.production}/manifest.toml";
    in
    # Use manifest data...
    [ pkgs.hello ];
}
```

### With sops-nix

```nix
{
  sops.secrets.flox-token = {
    sopsFile = ./secrets.yaml;
  };

  floxManifests = {
    enable = true;
    user = "myusername";
    environments = [ "default" ];
    tokenFile = config.sops.secrets.flox-token.path;
  };
}
```

### With agenix

```nix
{
  age.secrets.flox-token.file = ./secrets/flox-token.age;

  floxManifests = {
    enable = true;
    user = "myusername";
    environments = [ "default" ];
    tokenFile = config.age.secrets.flox-token.path;
  };
}
```

### Standalone (without NixOS/home-manager)

```bash
export FLOX_FLOXHUB_TOKEN="your-token"
nix-build examples/standalone.nix --impure
cat result/manifest.toml
```

### Using flox CLI for token

```nix
{
  floxManifests = {
    enable = true;
    user = "myusername";
    environments = [ "default" ];
    # Will automatically use 'flox auth token' as fallback
  };
}
```

Then build with:
```bash
home-manager switch --impure
```

## How It Works

1. **Authentication**: Resolves Flox Hub token from configured sources
2. **Fetching**: Uses `builtins.fetchGit` to fetch the floxmeta repository for each environment:
   ```nix
   builtins.fetchGit {
     url = "https://oauth:<token>@api.flox.dev/git/<user>/floxmeta";
     ref = environment;
   }
   ```
3. **Generation Discovery**: Uses `builtins.readDir` and Nix builtins to find the latest generation (highest numbered directory)
4. **Extraction**: Copies `manifest.toml` from `<generation>/env/manifest.toml` to the output
5. **Output**: Creates a derivation containing the manifest file and generation number

## Output Structure

Each manifest derivation contains:
```
$out/
├── manifest.toml    # The Flox manifest file
└── generation       # The generation number (e.g., "23")
```

## Security Considerations

- **Token visibility**: Using `token` option stores the token in the Nix store (world-readable)
- **Recommended**: Use `tokenFile` with a secrets management solution
- **Network access**: The module requires network access during evaluation (via `builtins.fetchGit`)
- **Token in URL**: Token is embedded in the git URL but not stored in derivation outputs

## Troubleshooting

### Error: "Could not resolve Flox token"

Make sure you've set one of:
- `floxManifests.token`
- `floxManifests.tokenFile`
- `FLOX_FLOXHUB_TOKEN` environment variable (with `--impure`)
- `~/.config/flox/flox.toml` with `floxhub_token` (with `--impure`)
- Working `flox` CLI installation (with `--impure`)

### Error: "No generation directories found"

The environment name doesn't exist or is empty. Check:
- The environment name matches a branch in your floxmeta repo
- You have access to the environment with your token

### Build fails with network errors

Ensure you have network access during Nix evaluation. `builtins.fetchGit` requires network connectivity to fetch the repository.

## Development

```bash
# Enter development shell
nix develop

# Format Nix files
nixpkgs-fmt .

# Test with an example
export FLOX_FLOXHUB_TOKEN="your-token"
nix-build examples/standalone.nix --impure
```

## Examples

See the [`examples/`](./examples/) directory for complete examples:
- [`home-manager.nix`](./examples/home-manager.nix) - Home Manager integration
- [`nixos.nix`](./examples/nixos.nix) - NixOS integration
- [`standalone.nix`](./examples/standalone.nix) - Standalone usage

## License

MIT

## Contributing

Contributions welcome! Please open an issue or pull request.

## Related Projects

- [Flox](https://github.com/flox/flox) - Developer environments you can take with you
- [home-manager](https://github.com/nix-community/home-manager) - Manage user environments with Nix
- [sops-nix](https://github.com/Mic92/sops-nix) - Secrets management with Nix
