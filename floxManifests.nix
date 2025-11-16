{ config, lib, ... }:

with lib;

let
  cfg = config.floxManifests;

  # Build list of manifest paths
  manifestPaths = map (env: "${cfg.cacheDir}/${env}/manifest.toml") cfg.environments;

in
{
  options.floxManifests = {
    enable = mkEnableOption "Flox manifest management";

    environments = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "default"
        "development"
      ];
      description = "List of Flox environment names";
    };

    cacheDir = mkOption {
      type = types.str;
      default = ".flox-manifests";
      example = "/etc/flox-manifests";
      description = "Directory where manifests are cached";
    };

    manifests = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      description = "List of paths to cached manifest directories";
    };
  };

  config = mkIf cfg.enable {
    floxManifests.manifests = manifestPaths;
  };
}
