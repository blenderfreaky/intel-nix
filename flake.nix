{
  description = "WIP Packaging of Intel LLVM, OneAPI and related tools for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-c.url = "github:blenderfreaky/nixpkgs/other/intel-cherry-picks-2";
    # nixpkgs.url = "github:NixOS/nixpkgs/staging";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-c,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        use-cherry-picked = false;
        pkgs =
          import (
            if use-cherry-picked
            then nixpkgs-c
            else nixpkgs
          ) {
            inherit system;

            overlays =
              if use-cherry-picked
              then []
              else [
                (final: prev: {
                  spirv-tools = prev.spirv-tools.overrideAttrs rec {
                    version = "1.4.321.0";

                    src = pkgs.fetchFromGitHub {
                      owner = "KhronosGroup";
                      repo = "SPIRV-Tools";
                      rev = "5e7108e11015b1e2c7d944f766524d19fb599b9d";
                      hash = "sha256-tn7+vzwLZ3MALFYWsBtDZCW0aoap1k4lZob50jI8dz8=";
                    };
                  };

                  spirv-headers = prev.spirv-headers.overrideAttrs {
                    # Not a real version, just bypasses the broken marker
                    version = "1.4.322";

                    src = pkgs.fetchFromGitHub {
                      owner = "KhronosGroup";
                      repo = "SPIRV-Headers";
                      # Latest commit on main branch as of 2025-08-10
                      rev = "a7361efd139bf65de0e86d43b01b01e0b34d387f";
                      hash = "sha256-Z03gXioXxtUviAmOXmPLHB/QaW3DQUGyaSXiAQj5UE4=";
                    };
                  };

                  ccacheWrapper = prev.ccacheWrapper.override {
                    extraConfig = ''
                      export CCACHE_COMPRESS=1
                      #export CCACHE_DIR="$ {config.programs.ccache.cacheDir}"
                      export CCACHE_DIR="/var/cache/ccache"
                      export CCACHE_UMASK=007
                      export CCACHE_SLOPPINESS=random_seed
                      if [ ! -d "$CCACHE_DIR" ]; then
                        echo "====="
                        echo "Directory '$CCACHE_DIR' does not exist"
                        echo "Please create it with:"
                        echo "  sudo mkdir -m0770 '$CCACHE_DIR'"
                        echo "  sudo chown root:nixbld '$CCACHE_DIR'"
                        echo "====="
                        exit 1
                      fi
                      if [ ! -w "$CCACHE_DIR" ]; then
                        echo "====="
                        echo "Directory '$CCACHE_DIR' is not accessible for user $(whoami)"
                        echo "Please verify its access permissions"
                        echo "====="
                        exit 1
                      fi
                    '';
                  };

                  #     # level-zero = prev.level-zero.overrideAttrs rec {
                  #     #   version = "1.24.2";

                  #     #   src = pkgs.fetchFromGitHub {
                  #     #     owner = "oneapi-src";
                  #     #     repo = "level-zero";
                  #     #     tag = "v${version}";
                  #     #     hash = "sha256-5QkXWuMFNsYNsW8lgo9FQIZ5NuLiRZCFKGWedpddi8Y=";
                  #     #   };
                  #     # };

                  #     # intel-compute-runtime = prev.intel-compute-runtime.overrideAttrs rec {
                  #     #   version = "25.05.32567.17";

                  #     #   src = pkgs.fetchFromGitHub {
                  #     #     owner = "intel";
                  #     #     repo = "compute-runtime";
                  #     #     rev = "${version}";
                  #     #     hash = "sha256-/9UQJ5Ng2ip+3cNcVZOtKAmnx4LpmPja+aTghIqF1bc=";
                  #     #   };
                  #     # };

                  #     # intel-compute-runtime = prev.intel-compute-runtime.overrideAttrs rec {
                  #     #   version = "25.05.32567.17";

                  #     #   src = pkgs.fetchFromGitHub {
                  #     #     owner = "intel";
                  #     #     repo = "compute-runtime";
                  #     #     rev = "${version}";
                  #     #     hash = "sha256-/9UQJ5Ng2ip+3cNcVZOtKAmnx4LpmPja+aTghIqF1bc=";
                  #     #   };
                  #     # };
                })
              ];
          };
      in {
        packages = {
          src = pkgs.callPackage ./src {};

          toolkits = pkgs.callPackage ./toolkits {};

          # deb = pkgs.callPackage ./deb { };
        };
      }
    );
}
