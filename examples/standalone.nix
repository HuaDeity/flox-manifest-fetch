# Example: Using the fetchFloxManifest function standalone
# This doesn't require NixOS or home-manager
#
# Usage:
#   nix-build examples/standalone.nix --impure
#   cat result/manifest.toml

{ pkgs ? import <nixpkgs> {} }:

let
  floxManifestFetch = import ../flake.nix;

  # Fetch a manifest directly using the helper function
  myManifest = floxManifestFetch.lib.fetchFloxManifest {
    inherit pkgs;
    user = "myusername";
    environment = "default";

    # Token from environment variable
    token = builtins.getEnv "FLOX_FLOXHUB_TOKEN";
  };

in
myManifest

# Alternative: Build multiple manifests
# {
#   default = floxManifestFetch.lib.fetchFloxManifest {
#     inherit pkgs;
#     user = "myusername";
#     environment = "default";
#     token = builtins.getEnv "FLOX_FLOXHUB_TOKEN";
#   };
#
#   development = floxManifestFetch.lib.fetchFloxManifest {
#     inherit pkgs;
#     user = "myusername";
#     environment = "development";
#     token = builtins.getEnv "FLOX_FLOXHUB_TOKEN";
#   };
# }
