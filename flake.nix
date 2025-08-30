{
  description = "WIP Packaging of Intel LLVM, OneAPI and related tools for Nix";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs.url = "github:NixOS/nixpkgs/staging";
    # nixpkgs-spirv.url = "github:NixOS/nixpkgs/pull/432015/head";
    #nixpkgs.url = "github:blenderfreaky/nixpkgs/other/intel-cherry-picks";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    # nixpkgs-spirv,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;

          overlays = [
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
