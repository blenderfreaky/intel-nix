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
}: let
  version = "b6089";
in
  llvm.stdenv.mkDerivation {
    pname = "llama-cpp";
    inherit version;

    src = fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      tag = "b6089";
      hash = "sha256-rNJpXydIdOtVdbtN0A8XCgcR2+s8JP5IznEp34gy68s=";
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
