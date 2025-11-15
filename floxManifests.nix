{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.floxManifests;

  # Fetch a single flox manifest from floxmeta repo
  fetchFloxManifest = { user, environment, token }:
    pkgs.stdenv.mkDerivation {
      name = "flox-manifest-${user}-${environment}";

      # Use git from nixpkgs
      nativeBuildInputs = [ pkgs.git pkgs.findutils pkgs.coreutils ];

      # Disable sandboxing to allow network access
      __noChroot = true;

      # We need network access
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = lib.fakeSha256; # Will need to be updated after first build

      buildCommand = ''
        set -euo pipefail

        # Clone the floxmeta repo for this environment
        echo "Cloning floxmeta for environment: ${environment}"
        git clone --depth 1 --branch "${environment}" \
          "https://oauth:${token}@api.flox.dev/git/${user}/floxmeta" \
          floxmeta 2>&1 | grep -v "oauth:" || true

        # Find the latest generation (highest number directory)
        cd floxmeta
        latest_gen=$(find . -maxdepth 1 -type d -regex '.*/[0-9]+' | \
                     sed 's|./||' | \
                     sort -n | \
                     tail -1)

        if [ -z "$latest_gen" ]; then
          echo "Error: No generation directories found in floxmeta" >&2
          exit 1
        fi

        echo "Found latest generation: $latest_gen"

        # Check if manifest exists
        manifest_path="$latest_gen/env/manifest.toml"
        if [ ! -f "$manifest_path" ]; then
          echo "Error: Manifest not found at $manifest_path" >&2
          exit 1
        fi

        # Copy manifest to output
        mkdir -p $out
        cp "$manifest_path" $out/manifest.toml
        echo "$latest_gen" > $out/generation

        echo "Successfully fetched manifest from generation $latest_gen"
      '';

      preferLocalBuild = false;
    };

  # Resolve token with fallback chain
  resolveToken =
    # 1. Direct token option (Pure)
    if cfg.token != null then
      cfg.token

    # 2. Token file (Pure if file is in store)
    else if cfg.tokenFile != null then
      builtins.readFile cfg.tokenFile

    # 3. Environment variable (Impure - requires --impure)
    else if builtins.getEnv "FLOX_FLOXHUB_TOKEN" != "" then
      builtins.getEnv "FLOX_FLOXHUB_TOKEN"

    # 4. Flox CLI (Impure - requires --impure and flox installed)
    else
      let
        # Try to get token from flox CLI
        tryFloxCli = pkgs.runCommand "flox-token-cli" {} ''
          if command -v ${cfg.floxBin} >/dev/null 2>&1; then
            ${cfg.floxBin} auth token > $out 2>/dev/null || echo "" > $out
          else
            echo "" > $out
          fi
        '';
        cliToken = lib.removeSuffix "\n" (builtins.readFile tryFloxCli);
      in
      if cliToken != "" then
        cliToken
      # 5. Config file (Impure - requires --impure)
      else
        let
          configPath = "${builtins.getEnv "HOME"}/.config/flox/flox.toml";
        in
        if builtins.pathExists configPath then
          let
            floxConfig = lib.importTOML configPath;
          in
          floxConfig.floxhub_token or (throw "floxhub_token not found in ${configPath}")
        else
          throw ''
            Could not resolve Flox token. Please use one of:
            1. Set floxManifests.token = "your-token"
            2. Set floxManifests.tokenFile = /path/to/token/file
            3. Set FLOX_FLOXHUB_TOKEN environment variable (requires --impure)
            4. Run 'flox auth token' (requires --impure)
            5. Configure ~/.config/flox/flox.toml with floxhub_token (requires --impure)
          '';

  # Build manifests for all environments
  manifestDerivations = listToAttrs (map
    (env: {
      name = env;
      value = fetchFloxManifest {
        user = cfg.user;
        environment = env;
        token = resolveToken;
      };
    })
    cfg.environments);

in
{
  options.floxManifests = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable Flox manifest fetcher.
        Fetches manifest.toml files from Flox environments.
      '';
    };

    user = mkOption {
      type = types.str;
      example = "myusername";
      description = ''
        Flox owner/username for the floxmeta repository.
      '';
    };

    environments = mkOption {
      type = types.listOf types.str;
      default = [ "default" ];
      example = [ "default" "development" "production" ];
      description = ''
        List of environment names (git branches) to fetch manifests from.
        Each environment corresponds to a branch in the floxmeta repository.
      '';
    };

    token = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Flox Hub token (takes highest priority).
        Note: This will be visible in the nix store. Use tokenFile for secrets.
      '';
    };

    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/flox-token";
      description = ''
        Path to file containing Flox Hub token.
        Preferred method for handling secrets.
      '';
    };

    floxBin = mkOption {
      type = types.str;
      default = "flox";
      example = "/home/user/.nix-profile/bin/flox";
      description = ''
        Flox binary path or name.
        Used as fallback if no token is provided via other methods.
        Requires --impure flag.
      '';
    };

    outputPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/etc/flox-manifests";
      description = ''
        Optional path to copy manifests to.
        If null, manifests are only available via the manifests attribute.
      '';
    };

    manifests = mkOption {
      type = types.attrsOf types.package;
      readOnly = true;
      internal = true;
      description = ''
        Output: Derivations containing manifest.toml files for each environment.
        Access via: config.floxManifests.manifests.<environment>

        Example usage:
          home.file."my-manifest".source =
            "''${config.floxManifests.manifests.default}/manifest.toml";
      '';
    };
  };

  config = mkIf cfg.enable {
    # Set the manifests output
    floxManifests.manifests = manifestDerivations;

    # Optionally copy manifests to outputPath
    # This would be used differently in NixOS vs home-manager
    # For now, users can access via the manifests attribute

    assertions = [
      {
        assertion = cfg.user != "";
        message = "floxManifests.user must be set";
      }
      {
        assertion = cfg.environments != [];
        message = "floxManifests.environments must not be empty";
      }
    ];
  };
}
