{callPackage}: rec {
  llvm-monolithic = callPackage ./llvm/monolithic.nix {};
  llvm-standalone = callPackage ./llvm/standalone.nix {};

  # llvm = llvm-standalone;
  llvm = llvm-monolithic;
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
  oneDNN = callPackage ./onednn.nix {intel-llvm = llvm;};
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
