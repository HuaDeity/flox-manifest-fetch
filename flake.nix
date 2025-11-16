{
  description = "Nix module for fetching Flox manifests";

  inputs = {
    nixpkgs.url = "github:flox/nixpkgs/stable";
    flox.url = "github:flox/flox/latest";
  };

  outputs =
    {
      self,
      nixpkgs,
      flox,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      flakeModules.floxManifests = import ./floxManifests.nix;

      # Packages for testing/examples
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Manifest fetcher script
          # Usage: nix run .#fetch-manifests -- --user myuser --envs default,development
          # Or: FLOX_USER=myuser FLOX_ENVS=default,development nix run .#fetch-manifests
          fetch-manifests = pkgs.writeShellApplication {
            name = "fetch-manifests";
            runtimeInputs = with pkgs; [
              git
              coreutils
              findutils
              flox.packages.${system}.default
            ];
            text = ''
              # Configuration
              CACHE_DIR="''${FLOX_CACHE_DIR:-.flox-manifests}"
              FLOX_USER="''${FLOX_USER:-}"
              FLOX_ENVS="''${FLOX_ENVS:-}"

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
                  --help|-h)
                    echo "Usage: fetch-manifests [OPTIONS]"
                    echo ""
                    echo "Fetch Flox manifests from FloxHub to local cache"
                    echo ""
                    echo "Options:"
                    echo "  --user USER         Flox username (auto-detected from 'flox auth status')"
                    echo "  --envs ENV1,ENV2    Comma-separated environments (required)"
                    echo "  --cache-dir DIR     Cache directory (default: .flox-manifests)"
                    echo "  --help, -h          Show this help"
                    echo ""
                    echo "Authentication:"
                    echo "  Username auto-detected from 'flox auth status'"
                    echo "  Token from 'flox auth token'"
                    echo "  Run 'flox auth login' first"
                    exit 0
                    ;;
                  *)
                    echo "Unknown option: $1" >&2
                    echo "Use --help for usage information" >&2
                    exit 1
                    ;;
                esac
              done

              # Auto-detect username from flox auth status if not provided
              if [ -z "$FLOX_USER" ]; then
                FLOX_USER=$(flox auth status 2>&1 | grep "logged in as" | awk '{print $6}')
              fi

              # Validate required parameters
              if [ -z "$FLOX_USER" ]; then
                echo "Error: Could not detect username" >&2
                echo "Either run 'flox auth login' or use --user option" >&2
                exit 1
              fi

              if [ -z "$FLOX_ENVS" ]; then
                echo "Error: FLOX_ENVS is required (use --envs or set FLOX_ENVS env var)" >&2
                exit 1
              fi

              # Get token from flox CLI
              TOKEN=$(flox auth token 2>/dev/null || echo "")
              if [ -z "$TOKEN" ]; then
                echo "Error: Failed to get token from 'flox auth token'" >&2
                echo "Run 'flox auth login' first" >&2
                exit 1
              fi

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

                ENV_CACHE="$CACHE_DIR/$env"
                TEMP_DIR=$(mktemp -d)

                # Clone the floxmeta repo
                if git clone --quiet --depth 1 --branch "$env" \
                  "https://oauth:$TOKEN@api.flox.dev/git/$FLOX_USER/floxmeta" \
                  "$TEMP_DIR" 2>&1 | sed "s/$TOKEN/[REDACTED]/g" | { grep -v "^Cloning into" || true; } >&2; then

                  cd "$TEMP_DIR"

                  # Find latest generation
                  latest_gen=$(find . -maxdepth 1 -type d -name '[0-9]*' -printf '%f\n' | sort -n | tail -1)

                  if [ -z "$latest_gen" ]; then
                    echo "Error: No generation directories found for $env" >&2
                    rm -rf "$TEMP_DIR"
                    exit 1
                  fi

                  # Check manifest exists
                  if [ ! -f "$latest_gen/env/manifest.toml" ]; then
                    echo "Error: Manifest not found for $env at generation $latest_gen" >&2
                    rm -rf "$TEMP_DIR"
                    exit 1
                  fi

                  # Create cache directory for this environment
                  mkdir -p "$ENV_CACHE"

                  # Copy manifest and generation info
                  cp "$latest_gen/env/manifest.toml" "$ENV_CACHE/manifest.toml"
                  echo "$latest_gen" > "$ENV_CACHE/generation"

                  # Simple output: just environment and generation
                  echo "$env: generation $latest_gen"

                  # Cleanup
                  cd - >/dev/null
                  rm -rf "$TEMP_DIR"
                else
                  echo "Error: Failed to fetch $env" >&2
                  rm -rf "$TEMP_DIR"
                  exit 1
                fi
              done
            '';
          };

          # Default package - the fetcher script
          default = self.packages.${system}.fetch-manifests;
        }
      );
    };
}
