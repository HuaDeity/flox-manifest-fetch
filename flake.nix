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
      # NixOS module
      nixosModules.floxManifests = import ./floxManifests.nix;
      nixosModules.default = self.nixosModules.floxManifests;

      # Home Manager module
      homeManagerModules.floxManifests = import ./floxManifests.nix;
      homeManagerModules.default = self.homeManagerModules.floxManifests;


      # Packages for testing/examples
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Manifest fetcher script
          # Usage: nix run .#fetch-manifests -- --user myuser --envs default,development
          # Or: FLOX_USER=myuser FLOX_ENVS=default,development nix run .#fetch-manifests
          fetch-manifests = pkgs.writeShellApplication {
            name = "fetch-manifests";
            runtimeInputs = with pkgs; [ git coreutils findutils ];
            text = ''
            # Configuration
            CACHE_DIR="''${FLOX_CACHE_DIR:-.flox-manifests}"
            FLOX_USER="''${FLOX_USER:-}"
            FLOX_ENVS="''${FLOX_ENVS:-}"
            TOKEN="''${FLOX_FLOXHUB_TOKEN:-}"

            # Parse command line arguments
            while [[ $# -gt 0 ]]; do
              case $1 in
                --user)
                  FLOX_USER="$2"
                  shift 2
                  ;;
                --envs)
                  FLOX_ENVS="$2"
                  shift 2
                  ;;
                --cache-dir)
                  CACHE_DIR="$2"
                  shift 2
                  ;;
                --token)
                  TOKEN="$2"
                  shift 2
                  ;;
                --help|-h)
                  echo "Usage: fetch-manifests [OPTIONS]"
                  echo ""
                  echo "Fetch Flox manifests from FloxHub to local cache"
                  echo ""
                  echo "Options:"
                  echo "  --user USER         Flox username (or set FLOX_USER)"
                  echo "  --envs ENV1,ENV2    Comma-separated environments (or set FLOX_ENVS)"
                  echo "  --cache-dir DIR     Cache directory (default: .flox-manifests)"
                  echo "  --token TOKEN       FloxHub token (or set FLOX_FLOXHUB_TOKEN)"
                  echo "  --help, -h          Show this help"
                  echo ""
                  echo "Token resolution (in order):"
                  echo "  1. --token argument"
                  echo "  2. FLOX_FLOXHUB_TOKEN environment variable"
                  echo "  3. flox auth token command"
                  echo "  4. ~/.config/flox/flox.toml"
                  exit 0
                  ;;
                *)
                  echo "Unknown option: $1" >&2
                  echo "Use --help for usage information" >&2
                  exit 1
                  ;;
              esac
            done

            # Validate required parameters
            if [ -z "$FLOX_USER" ]; then
              echo "Error: FLOX_USER is required (use --user or set FLOX_USER env var)" >&2
              exit 1
            fi

            if [ -z "$FLOX_ENVS" ]; then
              echo "Error: FLOX_ENVS is required (use --envs or set FLOX_ENVS env var)" >&2
              exit 1
            fi

            # Token resolution with fallback chain
            if [ -z "$TOKEN" ]; then
              echo "No token provided, trying fallback methods..."

              # Try flox CLI
              if command -v flox >/dev/null 2>&1; then
                echo "Trying: flox auth token"
                TOKEN=$(flox auth token 2>/dev/null || echo "")
              fi

              # Try config file
              if [ -z "$TOKEN" ] && [ -f "$HOME/.config/flox/flox.toml" ]; then
                echo "Trying: ~/.config/flox/flox.toml"
                TOKEN=$(grep '^floxhub_token' "$HOME/.config/flox/flox.toml" | cut -d'"' -f2 || echo "")
              fi

              if [ -z "$TOKEN" ]; then
                echo "Error: No token found. Set FLOX_FLOXHUB_TOKEN or run 'flox auth login'" >&2
                exit 1
              fi
            fi

            echo "==========================================="
            echo "  Flox Manifest Fetcher"
            echo "==========================================="
            echo "User: $FLOX_USER"
            echo "Environments: $FLOX_ENVS"
            echo "Cache directory: $CACHE_DIR"
            echo ""

            # Convert cache directory to absolute path
            if [[ "$CACHE_DIR" != /* ]]; then
              CACHE_DIR="$(pwd)/$CACHE_DIR"
            fi

            # Create cache directory
            mkdir -p "$CACHE_DIR"

            # Split environments by comma
            IFS=',' read -ra ENVS <<< "$FLOX_ENVS"

            # Fetch each environment
            for env in "''${ENVS[@]}"; do
              env=$(echo "$env" | xargs)  # trim whitespace
              echo "-------------------------------------------"
              echo "Fetching environment: $env"
              echo "-------------------------------------------"

              ENV_CACHE="$CACHE_DIR/$env"
              TEMP_DIR=$(mktemp -d)

              # Clone the floxmeta repo
              echo "Cloning floxmeta repository..."
              if git clone --depth 1 --branch "$env" \
                "https://oauth:$TOKEN@api.flox.dev/git/$FLOX_USER/floxmeta" \
                "$TEMP_DIR" 2>&1 | sed "s/$TOKEN/[REDACTED]/g"; then

                cd "$TEMP_DIR"

                # Find latest generation
                latest_gen=$(find . -maxdepth 1 -type d -name '[0-9]*' -printf '%f\n' | sort -n | tail -1)

                if [ -z "$latest_gen" ]; then
                  echo "Error: No generation directories found" >&2
                  rm -rf "$TEMP_DIR"
                  exit 1
                fi

                echo "Latest generation: $latest_gen"

                # Check manifest exists
                if [ ! -f "$latest_gen/env/manifest.toml" ]; then
                  echo "Error: Manifest not found at $latest_gen/env/manifest.toml" >&2
                  rm -rf "$TEMP_DIR"
                  exit 1
                fi

                # Create cache directory for this environment
                mkdir -p "$ENV_CACHE"

                # Copy manifest and generation info
                cp "$latest_gen/env/manifest.toml" "$ENV_CACHE/manifest.toml"
                echo "$latest_gen" > "$ENV_CACHE/generation"

                echo "✓ Cached manifest to: $ENV_CACHE"
                echo "  Generation: $latest_gen"

                # Cleanup
                cd - >/dev/null
                rm -rf "$TEMP_DIR"
              else
                echo "Error: Failed to clone repository" >&2
                rm -rf "$TEMP_DIR"
                exit 1
              fi

              echo ""
            done

            echo "==========================================="
            echo "  All manifests fetched successfully!"
            echo "==========================================="
            echo ""
            echo "Next steps:"
            echo "  1. Run your Nix builds (pure, no --impure needed):"
            echo "     nixos-rebuild switch"
            echo "     home-manager switch"
            echo ""
            echo "Cache directory contents:"
            ls -lah "$CACHE_DIR"
            '';
          };

          # Default package - the fetcher script
          default = self.packages.${system}.fetch-manifests;
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
