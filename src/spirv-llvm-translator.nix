{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchpatch,
  cmake,
  pkg-config,
  lit,
  llvm,
  spirv-headers,
  spirv-tools,
}: let
  llvmMajor = lib.versions.major llvm.version;
  isROCm = lib.hasPrefix "rocm" llvm.pname;

  # ROCm, if actively updated will always be at the latest version
  branch =
    if llvmMajor == "21"
    then rec {
      version = "21.1.0";
      rev = "v${version}";
      hash = "sha256-kk8BbPl/UBW1gaO/cuOQ9OsiNTEk0TkvRDLKUAh6exk=";
    }
    else if llvmMajor == "20"
    then rec {
      version = "20.1.5";
      rev = "v${version}";
      hash = "sha256-GdlC/Vl61nTNdua2s+CW2YOvkSKK6MNOvBc/393iths=";
    }
    else if llvmMajor == "19"
    then rec {
      version = "19.1.0";
      rev = "v${version}";
      hash = "sha256-uCUcWHXqzIkoT0t90WSm1QE8SzJWQ9sHN8it75GTph8=";
    }
    else if llvmMajor == "18" || isROCm
    then rec {
      version = "18.1.15";
      rev = "v${version}";
      hash = "sha256-rt3RTZut41uDEh0YmpOzH3sOezeEVWtAIGMKCHLSJBw=";
    }
    else if llvmMajor == "17"
    then rec {
      version = "17.0.15";
      rev = "v${version}";
      hash = "sha256-ETpTQYMMApECDfuRY87HrO/PUxZ13x9dBRJ3ychslUI=";
    }
    else if llvmMajor == "16"
    then rec {
      version = "16.0.15";
      rev = "v${version}";
      hash = "sha256-30i73tGl+1KlP92XA0uxdMTydd9EtaQ4SZ0W1kdm1fQ=";
    }
    else if llvmMajor == "15"
    then rec {
      version = "15.0.15";
      rev = "v${version}";
      hash = "sha256-kFVDS+qwoG1AXrZ8LytoiLVbZkTGR9sO+Wrq3VGgWNQ=";
    }
    else if llvmMajor == "14"
    then rec {
      version = "14.0.14";
      rev = "v${version}";
      hash = "sha256-PW+5w93omLYPZXjRtU4BNY2ztZ86pcjgUQZkrktMq+4=";
    }
    else if llvmMajor == "11"
    then rec {
      version = "11.0.4";
      rev = "v${version}";
      hash = "sha256-vvZG+yyPn59R5pym72q69VOKNaAnmTGCUq77dZ2Kh9c=";
    }
    else throw "Incompatible LLVM version.";
in
  stdenv.mkDerivation {
    pname = "SPIRV-LLVM-Translator";
    inherit (branch) version;

    src = fetchFromGitHub {
      owner = "KhronosGroup";
      repo = "SPIRV-LLVM-Translator";
      inherit (branch) rev hash;
    };

    patches =
      lib.optionals (llvmMajor == "18") [
        # Fixes build after SPV_INTEL_maximum_registers breaking change
        # TODO: remove on next spirv-headers release
        (fetchpatch {
          url = "https://github.com/KhronosGroup/SPIRV-LLVM-Translator/commit/d970c9126c033ebcbb7187bc705eae2e54726b74.patch";
          revert = true;
          hash = "sha256-71sJuGqVjTcB549eIiCO0LoqAgxkdEHCoxh8Pd/Qzz8=";
        })
      ]
      ++ lib.optionals (lib.versionAtLeast llvmMajor "16" && lib.versionOlder llvmMajor "18") [
        # Fixes build after spirv-headers breaking change
        (fetchpatch {
          url = "https://github.com/KhronosGroup/SPIRV-LLVM-Translator/commit/0166a0fb86dc6c0e8903436bbc3a89bc3273ebc0.patch";
          excludes = ["spirv-headers-tag.conf"];
          hash = "sha256-17JJG8eCFVphElY5fVT/79hj0bByWxo8mVp1ZNjQk/M=";
        })
      ]
      ++ lib.optionals (llvmMajor == "16") [
        # Fixes builds that link against external LLVM dynamic library
        (fetchpatch {
          url = "https://github.com/KhronosGroup/SPIRV-LLVM-Translator/commit/f3b9b604d7eda18d0d1029d94a6eebd33aa3a3fe.patch";
          hash = "sha256-opDjyZcy7O4wcSfm/A51NCIiDyIvbcmbv9ns1njdJbc=";
        })
      ]
      ++ lib.optionals (llvmMajor == "14") [
        (fetchpatch {
          # tries to install llvm-spirv into llvm nix store path
          url = "https://github.com/KhronosGroup/SPIRV-LLVM-Translator/commit/cce9a2f130070d799000cac42fe24789d2b777ab.patch";
          revert = true;
          hash = "sha256-GbFacttZRDCgA0jkUoFA4/B3EDn3etweKvM09OwICJ8=";
        })
      ];

    nativeBuildInputs =
      [
        pkg-config
        cmake
      ]
      ++ (
        if isROCm
        then [llvm]
        else [llvm.dev]
      );

    buildInputs =
      [
        spirv-headers
        spirv-tools
      ]
      ++ lib.optionals (!isROCm) [llvm];

    nativeCheckInputs = [lit];

    cmakeFlags =
      [
        "-DLLVM_INCLUDE_TESTS=ON"
        "-DLLVM_DIR=${(
          if isROCm
          then llvm
          else llvm.dev
        )}"
        "-DBUILD_SHARED_LIBS=YES"
        "-DLLVM_SPIRV_BUILD_EXTERNAL=YES"
        # RPATH of binary /nix/store/.../bin/llvm-spirv contains a forbidden reference to /build/
        "-DCMAKE_SKIP_BUILD_RPATH=ON"
      ]
      ++ lib.optional (llvmMajor != "11") "-DLLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR=${spirv-headers.src}"
      ++ lib.optional (llvmMajor == "19") "-DBASE_LLVM_VERSION=${lib.versions.majorMinor llvm.version}.0";

    # FIXME: CMake tries to run "/llvm-lit" which of course doesn't exist
    doCheck = false;

    makeFlags = [
      "all"
      "llvm-spirv"
    ];

    postInstall =
      ''
        install -D tools/llvm-spirv/llvm-spirv $out/bin/llvm-spirv
      ''
      + lib.optionalString stdenv.hostPlatform.isDarwin ''
        install_name_tool $out/bin/llvm-spirv \
          -change @rpath/libLLVMSPIRVLib.dylib $out/lib/libLLVMSPIRVLib.dylib
      '';

    meta = with lib; {
      homepage = "https://github.com/KhronosGroup/SPIRV-LLVM-Translator";
      description = "Tool and a library for bi-directional translation between SPIR-V and LLVM IR";
      mainProgram = "llvm-spirv";
      license = licenses.ncsa;
      platforms = platforms.unix;
      maintainers = with maintainers; [gloaming];
    };
  }
