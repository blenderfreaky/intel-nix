{
  lib,
  callPackage,
  # llvmPackages_11,
  llvmPackages_14,
  llvmPackages_15,
  llvmPackages_16,
  llvmPackages_17,
  llvmPackages_18,
  llvmPackages_19,
  llvmPackages_20,
  llvmPackages_21,
}: rec {
  llvm = callPackage ./llvm {inherit unified-runtime;};
  llvm-alt = callPackage ./llvm/alt.nix {
    inherit unified-runtime vc-intrinsics spirv-llvm-translator;
  };

  unified-runtime = callPackage ./unified-runtime.nix {inherit unified-memory-framework;};
  unified-memory-framework = callPackage ./unified-memory-framework.nix {inherit oneTBB;};

  hdr-histogram = callPackage ./hdr-histogram.nix {};
  emhash = callPackage ./emhash.nix {};
  vc-intrinsics = callPackage ./vc-intrinsics.nix {};

  oneMath-sycl-blas = callPackage ./onemath-sycl-blas.nix {inherit llvm;};
  oneMath = callPackage ./onemath.nix {
    inherit llvm oneMath-sycl-blas oneTBB;
  };
  oneDNN = callPackage ./onednn.nix {inherit llvm oneTBB;};
  oneTBB = callPackage ./onetbb.nix {
    #inherit llvm;
  };
  openvino = callPackage ./openvino.nix {};

  spirv-llvm-translator = callPackage ./spirv-llvm-translator.nix {};
  spirv-llvm-translator-test =
    lib.mapAttrs
    (
      _name: llvmPkg:
        spirv-llvm-translator.override {
          inherit (llvmPkg) llvm;
        }
    )
    {
      # llvmPackages_11
      "14" = llvmPackages_14;
      "15" = llvmPackages_15;
      "16" = llvmPackages_16;
      "17" = llvmPackages_17;
      "18" = llvmPackages_18;
      "19" = llvmPackages_19;
      "20" = llvmPackages_20;
      "21" = llvmPackages_21;
    };

  oneapi-ck = callPackage ./oneapi-ck.nix {};

  khronos-sycl-cts = callPackage ./khronos-sycl-cts.nix {mkDerivation = llvm.stdenv.mkDerivation;};

  # Unrelated to Intel, just for testing as it should hit most common use cases
  ggml = callPackage ./ggml/ggml.nix {
    inherit
      llvm
      oneDNN
      oneMath
      oneTBB
      ;
  };
  whisper-cpp = callPackage ./ggml/whisper-cpp.nix {
    inherit
      llvm
      oneDNN
      oneMath
      oneTBB
      openvino
      ;
  };
  llama-cpp = callPackage ./ggml/llama-cpp.nix {
    inherit
      llvm
      oneDNN
      oneMath
      oneTBB
      ;
  };
}
