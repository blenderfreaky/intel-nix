{
  kit,
  stdenvNoCC,
  wrapCC,
  symlinkJoin,
  makeWrapper,
}: let
  # Create wrappers for Intel compilers that need nixpkgs cc-wrapper treatment
  intelCompilerWrapper = stdenvNoCC.mkDerivation {
    name = "intel-compiler-unwrapped";
    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin

      # Find Intel compiler binaries - check multiple possible locations
      INTEL_BIN_PATHS=(
        "${kit}/compiler/latest/bin"
        "${kit}/compiler/latest/linux/bin"
        "${kit}/compiler/latest/linux/bin/intel64"
        "${kit}/opt/intel/oneapi/compiler/latest/linux/bin"
        "${kit}/opt/intel/oneapi/compiler/latest/linux/bin/intel64"
      )

      INTEL_BIN_DIR=""
      for path in "''${INTEL_BIN_PATHS[@]}"; do
        if [ -d "$path" ] && [ -f "$path/icx" ]; then
          INTEL_BIN_DIR="$path"
          break
        fi
      done

      if [ -z "$INTEL_BIN_DIR" ]; then
        echo "Could not find Intel compiler binaries in ${kit}"
        echo "Checked paths:"
        printf '%s\n' "''${INTEL_BIN_PATHS[@]}"
        find ${kit} -name "icx" -o -name "icpx" 2>/dev/null | head -5 || true
        exit 1
      fi

      echo "Found Intel compilers in: $INTEL_BIN_DIR"

      # Create symlinks to Intel compilers for cc-wrapper
      # We use icx/icpx as the base since they're the modern Intel compilers
      if [ -f "$INTEL_BIN_DIR/icx" ]; then
        ln -s "$INTEL_BIN_DIR/icx" $out/bin/clang
      fi
      if [ -f "$INTEL_BIN_DIR/icpx" ]; then
        ln -s "$INTEL_BIN_DIR/icpx" $out/bin/clang++
      fi

      # Also link other common names for compatibility
      if [ -f "$INTEL_BIN_DIR/icx" ]; then
        ln -s "$INTEL_BIN_DIR/icx" $out/bin/cc
        ln -s "$INTEL_BIN_DIR/icx" $out/bin/gcc
      fi
      if [ -f "$INTEL_BIN_DIR/icpx" ]; then
        ln -s "$INTEL_BIN_DIR/icpx" $out/bin/c++
        ln -s "$INTEL_BIN_DIR/icpx" $out/bin/g++
      fi
    '';

    passthru = {
      isClang = true;
      isIntel = true;
    };
  };

  # Wrap the Intel compiler with nixpkgs cc-wrapper for proper nix integration
  wrappedCompiler = wrapCC intelCompilerWrapper {
    # Intel compilers are LLVM-based
    isClang = true;
  };
in
  # Create a combined package with both the oneAPI toolkit and wrapped compilers
  symlinkJoin {
    name = "intel-oneapi-with-cc-wrapper";
    paths = [kit];

    nativeBuildInputs = [makeWrapper];

    postBuild = ''
      # Add the wrapped compiler to PATH while preserving Intel-specific compilers
      mkdir -p $out/nix-support

      # Expose the wrapped compiler for nixpkgs stdenv
      ln -sf ${wrappedCompiler}/nix-support/* $out/nix-support/ 2>/dev/null || true

      # Create wrapper scripts that preserve Intel compiler names but add nix integration
      INTEL_BIN_PATHS=(
        "$out/compiler/latest/bin"
        "$out/compiler/latest/linux/bin"
        "$out/compiler/latest/linux/bin/intel64"
        "$out/opt/intel/oneapi/compiler/latest/linux/bin"
        "$out/opt/intel/oneapi/compiler/latest/linux/bin/intel64"
      )

      for INTEL_BIN_DIR in "''${INTEL_BIN_PATHS[@]}"; do
        if [ -d "$INTEL_BIN_DIR" ]; then
          # Make directory writable for modifications
          chmod -R +w "$INTEL_BIN_DIR" 2>/dev/null || true

          # Wrap Intel compilers to use nix environment
          for compiler in icx icpx icc icpc; do
            if [ -f "$INTEL_BIN_DIR/$compiler" ] && [ ! -L "$INTEL_BIN_DIR/$compiler" ]; then
              echo "Wrapping Intel compiler: $compiler"
              mv "$INTEL_BIN_DIR/$compiler" "$INTEL_BIN_DIR/.$compiler-unwrapped"
              makeWrapper "$INTEL_BIN_DIR/.$compiler-unwrapped" "$INTEL_BIN_DIR/$compiler" \
                --prefix PATH : "${wrappedCompiler}/bin" \
                --set-default NIX_CC "${wrappedCompiler}"
            fi
          done
          break
        fi
      done
    '';

    passthru =
      kit.passthru
      // {
        cc = wrappedCompiler;
        isClang = true;
        isIntel = true;
      };
  }
