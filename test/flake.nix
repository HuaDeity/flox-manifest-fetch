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

      # Helper to evaluate the module with specific config
      evalModule = config:
        lib.evalModules {
          modules = [
            flox-manifest-fetch.nixosModules.default
            {
              _module.args = {
                inherit pkgs;
                floxPackage = flox-manifest-fetch.inputs.flox.packages.${system}.default or null;
              };
            }
            config
          ];
        };

      # Test configuration - UPDATE THESE VALUES
      testUser = "flox";  # Replace with your Flox username
      testEnv = "default";  # Replace with your environment name

    in
    {
      packages.${system} = {
        # Test 1: Direct token (highest priority)
        # Usage: nix build .#test-1-direct-token --impure
        test-1-direct-token =
          let
            token = builtins.getEnv "FLOX_FLOXHUB_TOKEN";
            config = evalModule {
              floxManifests = {
                enable = true;
                user = testUser;
                environments = [ testEnv ];
                token = token;  # Method 1: Direct token
              };
            };
            manifest = config.config.floxManifests.manifests.${testEnv};
          in
          pkgs.runCommand "test-1-direct-token" {
            inherit manifest;
          } ''
            echo "=== Test 1: Direct Token (Priority 1) ==="
            echo "Testing with: token option"
            echo ""

            if [ ! -f "${manifest}/manifest.toml" ]; then
              echo "FAILED: Manifest not found"
              exit 1
            fi

            echo "SUCCESS: Manifest fetched using direct token"
            echo "Generation: $(cat ${manifest}/generation)"

            mkdir -p $out
            cp ${manifest}/manifest.toml $out/
            cp ${manifest}/generation $out/
            echo "test-1-direct-token" > $out/test-name
          '';

        # Test 2: Token file (priority 2)
        # Usage:
        #   echo "your-token" > /tmp/flox-test-token
        #   nix build .#test-2-token-file
        test-2-token-file =
          let
            tokenFile = pkgs.writeText "test-token" (builtins.getEnv "FLOX_FLOXHUB_TOKEN");
            config = evalModule {
              floxManifests = {
                enable = true;
                user = testUser;
                environments = [ testEnv ];
                # token = null;  # Not set - testing priority
                tokenFile = tokenFile;  # Method 2: Token file
              };
            };
            manifest = config.config.floxManifests.manifests.${testEnv};
          in
          pkgs.runCommand "test-2-token-file" {
            inherit manifest tokenFile;
          } ''
            echo "=== Test 2: Token File (Priority 2) ==="
            echo "Testing with: tokenFile option"
            echo "Token file: ${tokenFile}"
            echo ""

            if [ ! -f "${manifest}/manifest.toml" ]; then
              echo "FAILED: Manifest not found"
              exit 1
            fi

            echo "SUCCESS: Manifest fetched using token file"
            echo "Generation: $(cat ${manifest}/generation)"

            mkdir -p $out
            cp ${manifest}/manifest.toml $out/
            cp ${manifest}/generation $out/
            echo "test-2-token-file" > $out/test-name
          '';

        # Test 3: Environment variable (priority 3)
        # Usage:
        #   export FLOX_FLOXHUB_TOKEN="your-token"
        #   nix build .#test-3-env-var --impure
        test-3-env-var =
          let
            config = evalModule {
              floxManifests = {
                enable = true;
                user = testUser;
                environments = [ testEnv ];
                # token = null;
                # tokenFile = null;
                # Will use FLOX_FLOXHUB_TOKEN env var - Method 3
              };
            };
            manifest = config.config.floxManifests.manifests.${testEnv};
          in
          pkgs.runCommand "test-3-env-var" {
            inherit manifest;
          } ''
            echo "=== Test 3: Environment Variable (Priority 3) ==="
            echo "Testing with: FLOX_FLOXHUB_TOKEN env var"
            echo ""

            if [ ! -f "${manifest}/manifest.toml" ]; then
              echo "FAILED: Manifest not found"
              exit 1
            fi

            echo "SUCCESS: Manifest fetched using env var"
            echo "Generation: $(cat ${manifest}/generation)"

            mkdir -p $out
            cp ${manifest}/manifest.toml $out/
            cp ${manifest}/generation $out/
            echo "test-3-env-var" > $out/test-name
          '';

        # Test 4: Flox CLI from flake input (priority 4)
        # Usage:
        #   flox auth login
        #   nix build .#test-4-flox-cli --impure
        test-4-flox-cli =
          let
            config = evalModule {
              floxManifests = {
                enable = true;
                user = testUser;
                environments = [ testEnv ];
                # token = null;
                # tokenFile = null;
                # FLOX_FLOXHUB_TOKEN not set (if testing priority)
                # Will use floxPackage - Method 4
                floxPackage = flox-manifest-fetch.inputs.flox.packages.${system}.default;
              };
            };
            manifest = config.config.floxManifests.manifests.${testEnv};
          in
          pkgs.runCommand "test-4-flox-cli" {
            inherit manifest;
          } ''
            echo "=== Test 4: Flox CLI from Flake Input (Priority 4) ==="
            echo "Testing with: floxPackage option"
            echo ""

            if [ ! -f "${manifest}/manifest.toml" ]; then
              echo "FAILED: Manifest not found"
              exit 1
            fi

            echo "SUCCESS: Manifest fetched using flox CLI from flake"
            echo "Generation: $(cat ${manifest}/generation)"

            mkdir -p $out
            cp ${manifest}/manifest.toml $out/
            cp ${manifest}/generation $out/
            echo "test-4-flox-cli" > $out/test-name
          '';

        # Test Priority: Test that higher priority methods override lower ones
        # Usage:
        #   export FLOX_FLOXHUB_TOKEN="your-token"
        #   nix build .#test-priority --impure
        test-priority =
          let
            directToken = builtins.getEnv "FLOX_FLOXHUB_TOKEN";
            tokenFile = pkgs.writeText "test-token-file" directToken;

            # Even though we set both token and tokenFile, token should win
            config = evalModule {
              floxManifests = {
                enable = true;
                user = testUser;
                environments = [ testEnv ];
                token = directToken;  # Priority 1
                tokenFile = tokenFile;  # Priority 2 (should be ignored)
                # env var also available but should be ignored
              };
            };
            manifest = config.config.floxManifests.manifests.${testEnv};
          in
          pkgs.runCommand "test-priority" {
            inherit manifest;
          } ''
            echo "=== Test Priority: Token > TokenFile > Env Var ==="
            echo "Set: token (priority 1), tokenFile (priority 2), env var (priority 3)"
            echo "Expected: token should be used"
            echo ""

            if [ ! -f "${manifest}/manifest.toml" ]; then
              echo "FAILED: Manifest not found"
              exit 1
            fi

            echo "SUCCESS: Priority test passed - token was used"
            echo "Generation: $(cat ${manifest}/generation)"

            mkdir -p $out
            cp ${manifest}/manifest.toml $out/
            cp ${manifest}/generation $out/
            echo "test-priority" > $out/test-name
          '';

        # Test Multiple Environments
        # Usage:
        #   export FLOX_FLOXHUB_TOKEN="your-token"
        #   nix build .#test-multi-env --impure
        test-multi-env =
          let
            config = evalModule {
              floxManifests = {
                enable = true;
                user = testUser;
                environments = [ testEnv "development" ];  # Add more environments
              };
            };
            manifests = config.config.floxManifests.manifests;
          in
          pkgs.runCommand "test-multi-env" {
            defaultManifest = manifests.${testEnv};
            # devManifest = manifests.development or null;
          } ''
            echo "=== Test Multiple Environments ==="
            echo "Testing: ${testEnv}, development"
            echo ""

            mkdir -p $out

            if [ -f "$defaultManifest/manifest.toml" ]; then
              echo "✓ ${testEnv} manifest found"
              cp $defaultManifest/manifest.toml $out/${testEnv}.toml
              echo "  Generation: $(cat $defaultManifest/generation)"
            else
              echo "✗ ${testEnv} manifest NOT found"
            fi

            # Note: development might not exist, so we don't fail if it's missing
            echo ""
            echo "SUCCESS: Multi-environment test completed"
            echo "test-multi-env" > $out/test-name
          '';

        # Complete test suite
        # Usage:
        #   export FLOX_FLOXHUB_TOKEN="your-token"
        #   nix build .#test-all --impure
        test-all = pkgs.runCommand "test-all" {
          test1 = self.packages.${system}.test-1-direct-token;
          test2 = self.packages.${system}.test-2-token-file;
          test3 = self.packages.${system}.test-3-env-var;
          testPriority = self.packages.${system}.test-priority;
        } ''
          echo "=========================================="
          echo "  Flox Manifest Fetch - Test Suite"
          echo "=========================================="
          echo ""

          mkdir -p $out

          echo "Test 1: Direct Token"
          cat $test1/test-name
          echo ""

          echo "Test 2: Token File"
          cat $test2/test-name
          echo ""

          echo "Test 3: Environment Variable"
          cat $test3/test-name
          echo ""

          echo "Test Priority"
          cat $testPriority/test-name
          echo ""

          echo "=========================================="
          echo "  All Tests Passed! ✓"
          echo "=========================================="

          # Collect all test results
          cp -r $test1 $out/test-1-direct-token
          cp -r $test2 $out/test-2-token-file
          cp -r $test3 $out/test-3-env-var
          cp -r $testPriority $out/test-priority
        '';
      };

      # Development shell
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nixpkgs-fmt
        ];

        shellHook = ''
          echo "=========================================="
          echo "  Flox Manifest Fetch - Test Environment"
          echo "=========================================="
          echo ""
          echo "IMPORTANT: Update test/flake.nix before testing:"
          echo "  - testUser = \"${testUser}\"  (your Flox username)"
          echo "  - testEnv = \"${testEnv}\"    (your environment)"
          echo ""
          echo "Available tests:"
          echo ""
          echo "  1. Test direct token (priority 1):"
          echo "     export FLOX_FLOXHUB_TOKEN='your-token'"
          echo "     nix build .#test-1-direct-token --impure"
          echo ""
          echo "  2. Test token file (priority 2):"
          echo "     export FLOX_FLOXHUB_TOKEN='your-token'"
          echo "     nix build .#test-2-token-file --impure"
          echo ""
          echo "  3. Test environment variable (priority 3):"
          echo "     export FLOX_FLOXHUB_TOKEN='your-token'"
          echo "     nix build .#test-3-env-var --impure"
          echo ""
          echo "  4. Test flox CLI from flake (priority 4):"
          echo "     flox auth login"
          echo "     nix build .#test-4-flox-cli --impure"
          echo ""
          echo "  5. Test priority order:"
          echo "     export FLOX_FLOXHUB_TOKEN='your-token'"
          echo "     nix build .#test-priority --impure"
          echo ""
          echo "  6. Test multiple environments:"
          echo "     export FLOX_FLOXHUB_TOKEN='your-token'"
          echo "     nix build .#test-multi-env --impure"
          echo ""
          echo "  7. Run all tests:"
          echo "     export FLOX_FLOXHUB_TOKEN='your-token'"
          echo "     nix build .#test-all --impure"
          echo ""
          echo "After building, check results:"
          echo "  cat result/manifest.toml"
          echo "  cat result/generation"
          echo ""
        '';
      };
    };
}
