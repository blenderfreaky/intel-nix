{
  lib,
  callPackage,
  pkgs,
}: rec {
  llvm-monolithic = callPackage ./llvm/monolithic.nix {inherit unified-runtime emhash vc-intrinsics;};
  llvm-standalone = callPackage ./llvm/standalone.nix {
    inherit unified-runtime vc-intrinsics emhash; # spirv-llvm-translator;
  };

  # llvm = llvm-standalone;
  llvm = llvm-monolithic;

  unified-runtime = callPackage ./unified-runtime.nix {
    inherit unified-memory-framework;
  };
  unified-memory-framework = callPackage ./unified-memory-framework.nix {};

  emhash = callPackage ./emhash.nix {};
  parallel-hashmap = callPackage ./parallel-hashmap.nix {};

  vc-intrinsics = callPackage ./vc-intrinsics.nix {};

  oneMath-sycl-blas = callPackage ./onemath-sycl-blas.nix {inherit llvm;};

  oneMath-sycl-blas-tuned = {
    intel = oneMath-sycl-blas.override {gpuTarget = "INTEL_GPU";};
    nvidia = oneMath-sycl-blas.override {gpuTarget = "NVIDIA_GPU";};
    amd = oneMath-sycl-blas.override {gpuTarget = "AMD_GPU";};
  };

  oneMath = callPackage ./onemath.nix {
    inherit llvm oneMath-sycl-blas;
  };
  oneDNN = callPackage ./onednn.nix {inherit llvm;};
  oneapi-ck = callPackage ./oneapi-ck.nix {};

  khronos-sycl-cts = callPackage ./khronos-sycl-cts.nix {mkDerivation = llvm.stdenv.mkDerivation;};

  # Unrelated to Intel, just for testing as it should hit most common use cases
  ggml = callPackage ./ggml/ggml.nix {
    inherit
      llvm
      oneDNN
      oneMath
      ;
  };
  whisper-cpp = callPackage ./ggml/whisper-cpp.nix {
    inherit
      llvm
      oneDNN
      oneMath
      ;
  };
  llama-cpp = callPackage ./ggml/llama-cpp.nix {
    inherit
      llvm
      oneDNN
      oneMath
      ;
  };
}
