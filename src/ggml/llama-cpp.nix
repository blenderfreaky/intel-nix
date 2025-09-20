{
  fetchFromGitHub,
  llvm,
  cmake,
  ninja,
  oneDNN,
  oneMath,
  oneTBB,
  mkl,
  git,
  opencl-headers,
  ocl-icd,
  curl,
}: let
  version = "b6524";
in
  llvm.stdenv.mkDerivation {
    pname = "llama-cpp";
    inherit version;

    src = fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      tag = "${version}";
      hash = "sha256-zxWjSwB1ueHLAhFDAW49k5V6vv2MvUz+CkK9/mxdfrI=";
    };

    nativeBuildInputs = [
      cmake
      ninja
      git
    ];

    buildInputs = [
      oneDNN
      oneMath
      oneTBB
      mkl
      opencl-headers
      ocl-icd
      curl
    ];

    hardeningDisable = [
      "zerocallusedregs"
      "pacret"
      # "shadowstack"
    ];

    cmakeFlags = [
      "-DGGML_SYCL=ON"
    ];
  }
