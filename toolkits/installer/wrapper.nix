{
  kit,
  stdenvNoCC,
  wrapCC,
}: let
  wrapper = wrapCC (
    stdenvNoCC.mkDerivation {
      name = "intel-compiler-wrapper";
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/bin
        cat > $out/bin/clang <<EOF
        #!/bin/sh
        exec "${kit}/compiler/latest/bin/compiler/clang" "\$@"
        EOF
        chmod +x $out/bin/clang
      '';
      passthru.isClang = true;
    }
  );
in
  #TODO: Use symlinkjoin
  stdenvNoCC.mkDerivation {
    unpackPhase = ''
      runHook preUnpack

      ln -s ${kit} $out

      runHook postUnpack
    '';

    buildPhase = ''
      runHook preBuild

      root=${kit}/compiler/latest/bin/compiler

      mv $root/clang $root/.clang-unwrapped

      # This is a hardlink to the same clang we just moved
      rm $root/clang-21

      ln -s ${wrapper}/bin/clang $root/clang
      ln -s ${wrapper}/bin/clang-21 $root/clang-21

      runHook postBuild
    '';
  }
