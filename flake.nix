{
  description = "Nix module for fetching Flox manifests";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      # NixOS module
      nixosModules.floxManifests = import ./floxManifests.nix;
      nixosModules.default = self.nixosModules.floxManifests;

      # Home Manager module
      homeManagerModules.floxManifests = import ./floxManifests.nix;
      homeManagerModules.default = self.homeManagerModules.floxManifests;

      # Example configurations for testing
      lib = {
        # Helper function to fetch a single manifest
        fetchFloxManifest = { pkgs, user, environment, token }:
          let
            module = import ./floxManifests.nix;
          in
          pkgs.stdenv.mkDerivation {
            name = "flox-manifest-${user}-${environment}";
            nativeBuildInputs = [ pkgs.git pkgs.findutils pkgs.coreutils ];
            __noChroot = true;
            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            outputHash = nixpkgs.lib.fakeSha256;

            buildCommand = ''
              set -euo pipefail

              echo "Cloning floxmeta for environment: ${environment}"
              git clone --depth 1 --branch "${environment}" \
                "https://oauth:${token}@api.flox.dev/git/${user}/floxmeta" \
                floxmeta 2>&1 | grep -v "oauth:" || true

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

              manifest_path="$latest_gen/env/manifest.toml"
              if [ ! -f "$manifest_path" ]; then
                echo "Error: Manifest not found at $manifest_path" >&2
                exit 1
              fi

              mkdir -p $out
              cp "$manifest_path" $out/manifest.toml
              echo "$latest_gen" > $out/generation

              echo "Successfully fetched manifest from generation $latest_gen"
            '';

            preferLocalBuild = false;
          };
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
