{
  fetchFromGitHub,
  llvm,
  cmake,
  ninja,
  oneDNN,
  oneMath,
  oneTBB,
  # mkl,
  git,
  opencl-headers,
  ocl-icd,
}: let
  version = "unstable-2025-09-19";
in
  llvm.stdenv.mkDerivation {
    pname = "whisper-cpp";
    inherit version;

    src = fetchFromGitHub {
      owner = "ggml-org";
      repo = "whisper.cpp";
      # tag = "v${version}";
      rev = "44fa2f647cf2a6953493b21ab83b50d5f5dbc483";
      hash = "sha256-1j8Z/fuxGkb3h21nwRJQ3HOS2/TfdjGo5Kaz41AM8js=";
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
      # mkl
      opencl-headers
      ocl-icd
      # llvm.baseLlvm.openmp
    ];

    hardeningDisable = [
      "zerocallusedregs"
      "pacret"
      # "shadowstack"
    ];

    cmakeFlags = [
      "-DWHISPER_SYCL=ON"
    ];
  }
