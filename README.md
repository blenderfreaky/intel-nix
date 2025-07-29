```sh
NIXPKGS_ALLOW_UNFREE=1 nix build --impure --print-build-logs .#toolkits.{base,hpc}
```

```sh
nix build --print-build-logs .#llvm
nix build --print-build-logs .#unified-runtime
nix build --print-build-logs .#unified-memory-framework
```
