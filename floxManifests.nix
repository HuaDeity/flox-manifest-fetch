{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.floxManifests;

  # Read manifest from cache directory (pure operation)
  readManifestFromCache = { user, environment, cacheDir }:
    let
      envCacheDir = "${toString cacheDir}/${environment}";
      manifestFile = "${envCacheDir}/manifest.toml";
      generationFile = "${envCacheDir}/generation";
    in
    if !builtins.pathExists envCacheDir then
      throw ''
        Manifest cache not found for environment '${environment}'.

        Run the fetch-manifests script first:
          nix run .#fetch-manifests -- --user ${user} --envs ${environment}

        Or with environment variables:
          FLOX_USER=${user} FLOX_ENVS=${environment} nix run .#fetch-manifests
      ''
    else if !builtins.pathExists manifestFile then
      throw ''
        Manifest file not found at: ${manifestFile}
        Cache directory exists but is missing manifest.toml.

        Re-run the fetch script:
          nix run .#fetch-manifests -- --user ${user} --envs ${environment}
      ''
    else
      # Create a derivation that copies the cached manifest
      pkgs.runCommand "flox-manifest-${user}-${environment}"
        {
          passthru = {
            inherit environment;
            generation = if builtins.pathExists generationFile
                        then lib.removeSuffix "\n" (builtins.readFile generationFile)
                        else "unknown";
          };
        }
        ''
          mkdir -p $out
          cp "${manifestFile}" $out/manifest.toml
          ${if builtins.pathExists generationFile then ''
            cp "${generationFile}" $out/generation
          '' else ''
            echo "unknown" > $out/generation
          ''}
        '';

  # Create manifest derivations for all configured environments
  manifestDerivations =
    if cfg.user == "" then
      throw "floxManifests.user must be set"
    else if cfg.environments == [] then
      throw "floxManifests.environments must not be empty"
    else
      listToAttrs (map
        (env: nameValuePair env (readManifestFromCache {
          user = cfg.user;
          environment = env;
          cacheDir = cfg.cacheDir;
        }))
        cfg.environments);

in
{
  options.floxManifests = {
    enable = mkEnableOption "Flox manifest fetching and management";

    user = mkOption {
      type = types.str;
      default = "";
      example = "myusername";
      description = ''
        Flox username for accessing FloxHub.
        This is used to identify which user's environments to fetch.
      '';
    };

    environments = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "default" "development" "production" ];
      description = ''
        List of Flox environment names to fetch manifests for.
        Each environment corresponds to a git branch in the floxmeta repository.
      '';
    };

    cacheDir = mkOption {
      type = types.path;
      default = ./.flox-manifests;
      defaultText = "./.flox-manifests";
      example = "/etc/flox-manifests";
      description = ''
        Directory where fetched manifests are cached.

        Manifests must be pre-fetched using the fetch-manifests script:
          nix run .#fetch-manifests -- --user USER --envs ENV1,ENV2

        The cache directory structure:
          .flox-manifests/
            default/
              manifest.toml
              generation
            development/
              manifest.toml
              generation
      '';
    };

    manifests = mkOption {
      type = types.attrsOf types.package;
      readOnly = true;
      description = ''
        Attribute set of manifest derivations, keyed by environment name.
        Each derivation contains the manifest.toml file and generation number.

        Access manifests like:
          config.floxManifests.manifests.default
          config.floxManifests.manifests.development
      '';
    };

    outputPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/etc/flox/manifests";
      description = ''
        Optional: Copy all manifests to this directory.
        Useful for making manifests available system-wide.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Set the manifests attribute
    floxManifests.manifests = manifestDerivations;

    # Optionally copy manifests to outputPath
    environment.etc = mkIf (cfg.outputPath != null) (
      listToAttrs (map
        (env: nameValuePair "flox/manifests/${env}.toml" {
          source = "${cfg.manifests.${env}}/manifest.toml";
        })
        cfg.environments)
    );
  };
}
