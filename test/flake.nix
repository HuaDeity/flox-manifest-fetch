{
  description = "Test configuration for flox-manifest-fetch module";

  inputs = {
    # Use local flox-manifest-fetch module
    flox-manifest-fetch.url = "path:..";

    # home-manager for testing
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "flox-manifest-fetch/nixpkgs";
    };
  };

  outputs = { self, flox-manifest-fetch, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = flox-manifest-fetch.inputs.nixpkgs.legacyPackages.${system};
    in
    {
      # Test 1: Standalone manifest fetch using the lib function
      packages.${system} = {
        # This demonstrates fetching a manifest without using the module
        # Usage:
        #   export FLOX_FLOXHUB_TOKEN="your-token"
        #   nix build .#test-manifest --impure
        test-manifest = flox-manifest-fetch.lib.fetchFloxManifest {
          inherit pkgs;
          user = "flox";  # Replace with your username
          environment = "default";
          token = builtins.getEnv "FLOX_FLOXHUB_TOKEN";
        };
      };

      # Test 2: home-manager configuration with the module
      homeConfigurations.testuser = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        modules = [
          flox-manifest-fetch.homeManagerModules.default

          {
            home.username = "testuser";
            home.homeDirectory = "/home/testuser";
            home.stateVersion = "23.11";

            # Configure floxManifests module
            floxManifests = {
              enable = true;
              user = "flox";  # Replace with your username
              environments = [ "default" ];

              # Option 1: Use token directly (for testing only - not secure!)
              # token = "your-token-here";

              # Option 2: Use token file (recommended)
              # tokenFile = /run/secrets/flox-token;

              # Option 3: Will use env var FLOX_FLOXHUB_TOKEN (requires --impure)
              # This is the default fallback

              # Option 4: Will use flox CLI from flake input (requires --impure)
              # Automatically available via floxPackage

              # Option 5: Will read from ~/.config/flox/flox.toml (requires --impure)
            };

            # Example: Copy the fetched manifest to home directory
            home.file."flox-manifest.toml" = {
              source = "${flox-manifest-fetch.homeManagerModules.default.config.floxManifests.manifests.default or ""}/manifest.toml";
              enable = false;  # Set to true to actually copy the file
            };

            # Print generation info
            home.sessionVariables = {
              # This will fail during build but shows how to access the data
              # FLOX_GEN = builtins.readFile "${config.floxManifests.manifests.default}/generation";
            };
          }
        ];
      };

      # Test 3: Check configuration
      checks.${system} = {
        # Verify the module loads correctly
        module-loads = pkgs.runCommand "test-module-loads" {} ''
          # Just test that the module can be imported
          echo "Testing module import..."
          ${pkgs.nix}/bin/nix-instantiate --eval -E '
            let
              module = import ${flox-manifest-fetch}/floxManifests.nix;
            in
            "success"
          ' > $out
        '';
      };

      # Development shells
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nixpkgs-fmt
          nix
        ];

        shellHook = ''
          echo "=== Flox Manifest Fetch Test Environment ==="
          echo ""
          echo "Available tests:"
          echo "  1. Standalone fetch:"
          echo "     export FLOX_FLOXHUB_TOKEN='your-token'"
          echo "     nix build .#test-manifest --impure"
          echo "     cat result/manifest.toml"
          echo ""
          echo "  2. Home-manager config:"
          echo "     export FLOX_FLOXHUB_TOKEN='your-token'"
          echo "     nix build .#homeConfigurations.testuser.activationPackage --impure"
          echo ""
          echo "  3. Check module loads:"
          echo "     nix build .#checks.${system}.module-loads"
          echo ""
          echo "Note: Replace 'flox' with your actual Flox username in test/flake.nix"
          echo ""
        '';
      };
    };
}
