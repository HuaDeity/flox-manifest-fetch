# Example: Using floxManifests with home-manager
#
# Add to your flake.nix inputs:
#   inputs.flox-manifest-fetch.url = "github:yourusername/flox-manifest-fetch";
#
# Then in your home-manager configuration:

{ config, pkgs, ... }:

{
  imports = [
    # Import the floxManifests module
    # inputs.flox-manifest-fetch.homeManagerModules.default
  ];

  # Example 1: Using token file (Pure - Recommended for secrets)
  floxManifests = {
    enable = true;
    user = "myusername";
    environments = [ "default" "development" ];
    tokenFile = /run/secrets/flox-token;  # Could be from sops-nix or agenix
  };

  # Example 2: Using direct token (Pure - Not recommended for secrets)
  # floxManifests = {
  #   enable = true;
  #   user = "myusername";
  #   environments = [ "default" ];
  #   token = "flox_your_token_here";  # Will be visible in nix store!
  # };

  # Example 3: Using environment variable (Impure - requires --impure)
  # floxManifests = {
  #   enable = true;
  #   user = "myusername";
  #   environments = [ "default" ];
  #   # Will automatically try FLOX_FLOXHUB_TOKEN env var
  # };

  # Example 4: Using flox CLI (Impure - requires --impure)
  # The module includes flox from the flake input, so it will use it automatically
  # floxManifests = {
  #   enable = true;
  #   user = "myusername";
  #   environments = [ "default" ];
  #   # Will use 'flox auth token' from flake input as fallback
  #   # Or override with custom package:
  #   # floxPackage = inputs.my-flox.packages.${pkgs.system}.default;
  # };

  # Example 5: Using ~/.config/flox/flox.toml (Impure - requires --impure)
  # floxManifests = {
  #   enable = true;
  #   user = "myusername";
  #   environments = [ "default" ];
  #   # Will read from ~/.config/flox/flox.toml as last fallback
  # };

  # Usage: Access fetched manifests

  # Copy manifest to a file
  home.file."flox-default-manifest.toml".source =
    "${config.floxManifests.manifests.default}/manifest.toml";

  # Copy manifest with custom name
  home.file."my-dev-env.toml".source =
    "${config.floxManifests.manifests.development}/manifest.toml";

  # Read and parse manifest content in config
  # (example: use manifest data in other modules)
  home.sessionVariables = {
    FLOX_ENV_GENERATION = builtins.readFile "${config.floxManifests.manifests.default}/generation";
  };

  # Advanced: Parse the TOML manifest
  # programs.myapp.config =
  #   let
  #     manifest = pkgs.lib.importTOML "${config.floxManifests.manifests.default}/manifest.toml";
  #   in
  #   {
  #     # Use manifest data here
  #   };
}
