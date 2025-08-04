Work in progress packaging of Intel oneAPI Suite for NixOS

Not stable yet

# Toolkits, via installer

```sh
NIXPKGS_ALLOW_UNFREE=1 nix build --impure --print-build-logs .#toolkits.{base,hpc}
```

# Open source compiler and libraries, built from source

Provides an `stdenv` for derivations and co via `src.llvm.stdenv`

```sh
nix build --print-build-logs .#src.llvm
nix build --print-build-logs .#src.{oneMath,oneDNN}
```

# Closed source compiler and libraries, from intel apt repository

TODO

```sh
nix build --print-build-logs .#deb.*
```
