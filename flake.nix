{
  description = "WIP Packaging of Intel LLVM, OneAPI and related tools for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages = rec {
          llvm = pkgs.callPackage ./llvm { inherit unified-runtime; };
          unified-runtime = pkgs.callPackage ./unified-runtime.nix { inherit unified-memory-framework; };
          unified-memory-framework = pkgs.callPackage ./unified-memory-framework.nix { };

          toolkits = pkgs.callPackage ./toolkits { };
        };
      }
    );
}
