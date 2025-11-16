{
  description = "Nix module for fetching Flox manifests";

  inputs = {
    # Use Flox's nixpkgs fork for better compatibility
    nixpkgs.url = "github:flox/nixpkgs/stable";

    # Flox CLI for token resolution fallback
    flox = {
      url = "github:flox/flox";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flox }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      # NixOS module - with flox package injected
      nixosModules.floxManifests = { pkgs, ... }: {
        imports = [ (import ./floxManifests.nix) ];
        config._module.args.floxPackage = flox.packages.${pkgs.system}.default or null;
      };
      nixosModules.default = self.nixosModules.floxManifests;

      # Home Manager module - with flox package injected
      homeManagerModules.floxManifests = { pkgs, ... }: {
        imports = [ (import ./floxManifests.nix) ];
        config._module.args.floxPackage = flox.packages.${pkgs.system}.default or null;
      };
      homeManagerModules.default = self.homeManagerModules.floxManifests;

      # Example configurations for testing
      lib = {
        # Helper function to fetch a single manifest
        fetchFloxManifest = { pkgs, user, environment, token }:
          let
            lib = nixpkgs.lib;

            # Fetch the floxmeta repo for this environment using builtins.fetchGit
            floxmeta = builtins.fetchGit {
              url = "https://oauth:${token}@api.flox.dev/git/${user}/floxmeta";
              ref = environment;
            };

            # Read the directory entries
            entries = builtins.readDir floxmeta;

            # Filter for numeric directory names (generations)
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
      };

      # Packages for testing/examples
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Example: fetch a specific manifest directly
          # Usage: nix build .#example-manifest --impure
          example-manifest = self.lib.fetchFloxManifest {
            inherit pkgs;
            user = "example-user";
            environment = "default";
            token = builtins.getEnv "FLOX_FLOXHUB_TOKEN";
          };
        }
      );

      # Dev shell
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              git
              nixpkgs-fmt
            ];

            shellHook = ''
              echo "Flox Manifest Fetch development environment"
              echo "Available commands:"
              echo "  nixpkgs-fmt - Format nix files"
              echo ""
              echo "Example usage:"
              echo "  nix eval --impure .#example-manifest"
            '';
          };
        }
      );

      # Formatter
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
