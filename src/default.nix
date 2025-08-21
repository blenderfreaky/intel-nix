{
  lib,
  callPackage,
  pkgs,
}: rec {
  llvm-prev = callPackage ./llvm {inherit unified-runtime vc-intrinsics emhash;};
  llvm = callPackage ./llvm/alt.nix {
    inherit unified-runtime vc-intrinsics emhash; # spirv-llvm-translator;
  };

  unified-runtime = callPackage ./unified-runtime.nix {
    inherit unified-memory-framework hdr-histogram;
  };
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

  spirv-llvm-translator = callPackage ./spirv-llvm-translator.nix {};

  spirv-llvm-translator-tests = lib.genAttrs [
    "14"
    "15"
    "16"
    "17"
    "18"
    "19"
    "20"
    "21"
  ] (version: spirv-llvm-translator.override {llvm = pkgs."llvm_${version}";});
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
