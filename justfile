[private]
@default:
  just --choose

# Auto-detect hostname
hostname := `hostname -s`

nix_options := (
  '--flake . ' +
  '--option accept-flake-config true ' +
  '--option extra-experimental-features "flakes nix-command"'
)

# Fetch Flox manifests from configuration
[private]
fetch-manifests config-path:
    #!/usr/bin/env bash
    set -euo pipefail

    # Check if floxManifests is enabled
    enabled=$(nix eval --raw "{{config-path}}.config.floxManifests.enable" 2>/dev/null || echo "false")

    if [ "$enabled" != "true" ]; then
        echo "ℹ️  floxManifests not enabled, skipping fetch"
        exit 0
    fi

    echo "📦 Fetching Flox manifests from {{config-path}}..."

    # Get environments and join with commas
    envs=$(nix eval --raw "{{config-path}}.config.floxManifests.environments" --apply 'envs: builtins.concatStringsSep "," envs')

    # Get cache directory
    cache_dir=$(nix eval --raw "{{config-path}}.config.floxManifests.cacheDir")

    if [ -z "$envs" ]; then
        echo "ℹ️  No environments configured, skipping fetch"
        exit 0
    fi

    echo "  Environments: $envs"
    echo "  Cache dir: $cache_dir"
    echo ""

    # Run fetch-manifests
    nix run .#fetch-manifests -- --envs "$envs" --cache-dir "$cache_dir"

[private]
[macos]
@update-manifests:
  just fetch-manifests '.#darwinConfigurations.{{hostname}}'

[private]
[linux]
@update-manifests:
  just fetch-manifests '.#nixosConfigurations.{{hostname}}'

# Update home-manager configuration
@update-home user=(env_var('USER')):
  just fetch-manifests '.#homeConfigurations."{{user}}@{{hostname}}"'

update:
  nix flake update
  just update-manifests

# Wrapper around {nixos,darwin}-rebuild, always taking the flake
[private]
[macos]
rebuild *args:
  darwin-rebuild {{nix_options}} {{args}} |& nom

[private]
[linux]
rebuild *args:
  nixos-rebuild --use-remote-sudo {{nix_options}} {{args}} |& nom

@build *args:
  just update
  just rebuild build {{args}}
  nvd diff /run/current-system result

home *args:
  home-manager {{nix_options}} {{args}} |& nom

[linux]
@boot *args:
  just rebuild boot {{args}}

[macos]
@check *args:
  just rebuild check {{args}}

[linux]
@check *args:
  just rebuild dry-build {{args}}

@switch *args:
  just build {{args}}
  just confirm-switch {{args}}

[confirm]
[private]
@confirm-switch *args:
  just rebuild switch {{args}}

clean:
  nix-env --profile /nix/var/nix/profiles/system --delete-generations old
  nix-collect-garbage -d
  nix store optimise
