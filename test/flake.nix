{
  description = "Test configuration for flox-manifest-fetch module";

  inputs = {
    # Use local flox-manifest-fetch module
    flox-manifest-fetch.url = "path:..";
  };

  outputs = { self, flox-manifest-fetch, ... }:
    let
      system = "x86_64-linux";
      pkgs = flox-manifest-fetch.inputs.nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      # Test configuration - UPDATE THESE VALUES
      testUser = "flox";  # Replace with your Flox username
      testEnv = "default";  # Replace with your environment name
      cacheDir = ./.flox-manifests;  # Where fetch-manifests will store manifests

      # Helper to evaluate the module with specific config
      evalModule = config:
        lib.evalModules {
          modules = [
            flox-manifest-fetch.nixosModules.default
            {
              _module.args = { inherit pkgs; };
            }
            config
          ];
        };

    in
    {
      packages.${system} = {
        # Test 1: Basic manifest reading from cache
        # Prerequisites:
        #   1. Run: nix run ..#fetch-manifests -- --user flox --envs default
        #   2. This creates .flox-manifests/default/manifest.toml
        # Usage: nix build .#test-basic
        test-basic =
          let
            config = evalModule {
              floxManifests = {
                enable = true;
                user = testUser;
                environments = [ testEnv ];
                cacheDir = cacheDir;
              };
            };
            manifest = config.config.floxManifests.manifests.${testEnv};
          in
          pkgs.runCommand "test-basic" {
            inherit manifest;
          } ''
            echo "=== Test: Basic Manifest Reading ==="
            echo "User: ${testUser}"
            echo "Environment: ${testEnv}"
            echo ""

            if [ ! -f "${manifest}/manifest.toml" ]; then
              echo "FAILED: Manifest not found"
              echo "Did you run 'nix run ..#fetch-manifests -- --user ${testUser} --envs ${testEnv}' first?"
              exit 1
            fi

            echo "SUCCESS: Manifest loaded from cache"
            echo "Generation: $(cat ${manifest}/generation)"
            echo ""

            mkdir -p $out
            cp ${manifest}/manifest.toml $out/
            cp ${manifest}/generation $out/
            echo "test-basic" > $out/test-name

            echo "Manifest preview:"
            head -20 ${manifest}/manifest.toml
          '';

        # Test 2: Multiple environments
        # Prerequisites: nix run ..#fetch-manifests -- --user flox --envs default,development
        # Usage: nix build .#test-multi-env
        test-multi-env =
          let
            config = evalModule {
              floxManifests = {
                enable = true;
                user = testUser;
                environments = [ testEnv "development" ];
                cacheDir = cacheDir;
              };
            };
            manifests = config.config.floxManifests.manifests;
          in
          pkgs.runCommand "test-multi-env" {
            defaultManifest = manifests.${testEnv} or null;
            devManifest = manifests.development or null;
          } ''
            echo "=== Test: Multiple Environments ==="
            echo "Environments: ${testEnv}, development"
            echo ""

            mkdir -p $out

            if [ -n "$defaultManifest" ] && [ -f "$defaultManifest/manifest.toml" ]; then
              echo "✓ ${testEnv} manifest loaded"
              cp $defaultManifest/manifest.toml $out/${testEnv}.toml
              echo "  Generation: $(cat $defaultManifest/generation)"
            else
              echo "✗ ${testEnv} manifest NOT loaded"
            fi

            if [ -n "$devManifest" ] && [ -f "$devManifest/manifest.toml" ]; then
              echo "✓ development manifest loaded"
              cp $devManifest/manifest.toml $out/development.toml
              echo "  Generation: $(cat $devManifest/generation)"
            else
              echo "✗ development manifest NOT loaded (may not exist)"
            fi

            echo ""
            echo "SUCCESS: Multi-environment test completed"
            echo "test-multi-env" > $out/test-name
          '';

        # Test 3: Custom cache directory
        # Usage:
        #   FLOX_CACHE_DIR=/tmp/my-cache nix run ..#fetch-manifests -- --user flox --envs default
        #   nix build .#test-custom-cache --impure
        test-custom-cache =
          let
            customCache = /tmp/flox-test-cache;
            config = evalModule {
              floxManifests = {
                enable = true;
                user = testUser;
                environments = [ testEnv ];
                cacheDir = customCache;
              };
            };
            manifest = config.config.floxManifests.manifests.${testEnv};
          in
          pkgs.runCommand "test-custom-cache" {
            inherit manifest;
          } ''
            echo "=== Test: Custom Cache Directory ==="
            echo "Cache directory: ${toString customCache}"
            echo ""

            if [ ! -f "${manifest}/manifest.toml" ]; then
              echo "FAILED: Manifest not found in custom cache"
              exit 1
            fi

            echo "SUCCESS: Manifest loaded from custom cache directory"
            echo "Generation: $(cat ${manifest}/generation)"

            mkdir -p $out
            cp ${manifest}/manifest.toml $out/
            cp ${manifest}/generation $out/
            echo "test-custom-cache" > $out/test-name
          '';

        # Complete test suite
        # Usage: nix build .#test-all
        test-all = pkgs.runCommand "test-all" {
          test1 = self.packages.${system}.test-basic;
          test2 = self.packages.${system}.test-multi-env;
        } ''
          echo "=========================================="
          echo "  Flox Manifest Fetch - Test Suite"
          echo "=========================================="
          echo ""

          mkdir -p $out

          echo "Test 1: Basic Manifest Reading"
          if [ -f "$test1/test-name" ]; then
            cat $test1/test-name
            echo " ✓ PASSED"
          else
            echo " ✗ FAILED"
          fi
          echo ""

          echo "Test 2: Multiple Environments"
          if [ -f "$test2/test-name" ]; then
            cat $test2/test-name
            echo " ✓ PASSED"
          else
            echo " ✗ FAILED"
          fi
          echo ""

          echo "=========================================="
          echo "  All Tests Completed"
          echo "=========================================="

          # Collect all test results
          cp -r $test1 $out/test-basic
          cp -r $test2 $out/test-multi-env
        '';
      };

      # Development shell
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          git
          nixpkgs-fmt
        ];

        shellHook = ''
          echo "=========================================="
          echo "  Flox Manifest Fetch - Test Environment"
          echo "=========================================="
          echo ""
          echo "IMPORTANT: This module uses a two-step workflow:"
          echo ""
          echo "Step 1: Fetch manifests (run once or when they change)"
          echo "  cd .."
          echo "  nix run .#fetch-manifests -- --user ${testUser} --envs ${testEnv}"
          echo ""
          echo "  Or with environment variables:"
          echo "  FLOX_USER=${testUser} FLOX_ENVS=${testEnv} nix run .#fetch-manifests"
          echo ""
          echo "Step 2: Run tests (pure Nix, no --impure needed!)"
          echo "  cd test"
          echo "  nix build .#test-basic"
          echo "  nix build .#test-multi-env"
          echo "  nix build .#test-all"
          echo ""
          echo "Update testUser and testEnv in test/flake.nix before testing"
          echo ""
        '';
      };
    };
}
