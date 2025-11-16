{ config, lib, pkgs, floxPackage ? null, ... }:

with lib;

let
  cfg = config.floxManifests;

  # Fetch a single flox manifest from floxmeta repo using builtins.fetchGit
  fetchFloxManifest = { user, environment, token }:
    let
      # Fetch the floxmeta repo for this environment using builtins.fetchGit
      floxmeta = builtins.fetchGit {
        url = "https://oauth:${token}@api.flox.dev/git/${user}/floxmeta";
        ref = environment;
        # shallow = true; # Not all Nix versions support this
      };

      # Read the directory entries
      entries = builtins.readDir floxmeta;

      # Filter for numeric directory names (generations)
      # entries is an attrset like { "1" = "directory"; "23" = "directory"; ... }
      generations = lib.filterAttrs (name: type:
        type == "directory" && builtins.match "[0-9]+" name != null
      ) entries;

      # Get list of generation numbers as integers
      generationNumbers = map lib.toInt (builtins.attrNames generations);

      # Find the latest (maximum) generation
      latestGeneration =
        if generationNumbers == [] then
          throw "No generation directories found in floxmeta for ${user}/${environment}"
        else
          toString (lib.foldl lib.max 0 generationNumbers);

      # Path to the manifest
      manifestPath = "${floxmeta}/${latestGeneration}/env/manifest.toml";

    in
    # Create a derivation that copies the manifest
    pkgs.runCommand "flox-manifest-${user}-${environment}" {
      inherit latestGeneration;
      passthru = {
        inherit floxmeta latestGeneration;
      };
    } ''
      if [ ! -f "${manifestPath}" ]; then
        echo "Error: Manifest not found at ${manifestPath}" >&2
        exit 1
      fi

      mkdir -p $out
      cp "${manifestPath}" $out/manifest.toml
      echo "${latestGeneration}" > $out/generation
    '';

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
        # Determine which flox binary to use
        floxExe =
          if cfg.floxPackage != null then
            "${cfg.floxPackage}/bin/flox"
          else
            cfg.floxBin;

        # Try to get token from flox CLI
        tryFloxCli = pkgs.runCommand "flox-token-cli" {} ''
          if command -v ${floxExe} >/dev/null 2>&1; then
            ${floxExe} auth token > $out 2>/dev/null || echo "" > $out
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

    floxPackage = mkOption {
      type = types.nullOr types.package;
      default = floxPackage;
      defaultText = "flox package from flake input";
      description = ''
        Flox package to use for 'flox auth token' command.
        Defaults to the flox package from the flake input.
        Used as fallback if no token is provided via other methods.
      '';
    };

    floxBin = mkOption {
      type = types.str;
      default = "flox";
      example = "/home/user/.nix-profile/bin/flox";
      description = ''
        Flox binary path or name (fallback if floxPackage is not available).
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

  config = mkIf cfg.enable (mkMerge [
    {
      # Validate configuration
      _module.args = {
        # Basic validation via assertions in the value itself
        # This works even without NixOS/home-manager assertions support
      };

      # Set the manifests output
      floxManifests.manifests =
        if cfg.user == "" then
          throw "floxManifests.user must be set"
        else if cfg.environments == [] then
          throw "floxManifests.environments must not be empty"
        else
          manifestDerivations;

      # Optionally copy manifests to outputPath
      # This would be used differently in NixOS vs home-manager
      # For now, users can access via the manifests attribute
    }

    # Only add assertions if running in NixOS/home-manager context
    # (optional assertions support for better error messages)
    (mkIf (options ? assertions) {
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
    })
  ]);
}
