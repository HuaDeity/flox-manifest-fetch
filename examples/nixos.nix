# Example: Using floxManifests with NixOS
#
# Add to your flake.nix inputs:
#   inputs.flox-manifest-fetch.url = "github:yourusername/flox-manifest-fetch";
#
# Then in your NixOS configuration:

{ config, pkgs, lib, ... }:

{
  imports = [
    # Import the floxManifests module
    # inputs.flox-manifest-fetch.nixosModules.default
  ];

  # Configure floxManifests
  floxManifests = {
    enable = true;
    user = "myorganization";
    environments = [ "production" "staging" ];

    # Use a secret management solution for the token
    tokenFile = "/run/secrets/flox-token";
  };

  # Example: Create system files from manifests
  environment.etc."flox/production-manifest.toml".source =
    "${config.floxManifests.manifests.production}/manifest.toml";

  environment.etc."flox/staging-manifest.toml".source =
    "${config.floxManifests.manifests.staging}/manifest.toml";

  # Example: Use with sops-nix for secret management
  # sops.secrets.flox-token = {
  #   sopsFile = ./secrets.yaml;
  # };
  #
  # floxManifests.tokenFile = config.sops.secrets.flox-token.path;

  # Example: Use with agenix for secret management
  # age.secrets.flox-token.file = ./secrets/flox-token.age;
  # floxManifests.tokenFile = config.age.secrets.flox-token.path;

  # Example: Create a systemd service that uses the manifest
  systemd.services.flox-manifest-sync = {
    description = "Sync Flox manifests";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "sync-flox-manifests" ''
        echo "Production manifest generation: $(cat ${config.floxManifests.manifests.production}/generation)"
        echo "Staging manifest generation: $(cat ${config.floxManifests.manifests.staging}/generation)"

        # Copy manifests to a custom location
        mkdir -p /var/lib/flox-manifests
        cp ${config.floxManifests.manifests.production}/manifest.toml /var/lib/flox-manifests/production.toml
        cp ${config.floxManifests.manifests.staging}/manifest.toml /var/lib/flox-manifests/staging.toml
      '';
    };
  };

  # Example: Parse manifest and use in configuration
  # environment.systemPackages =
  #   let
  #     manifest = lib.importTOML "${config.floxManifests.manifests.production}/manifest.toml";
  #   in
  #   # Extract packages from manifest or use manifest data
  #   [ pkgs.hello ];
}
