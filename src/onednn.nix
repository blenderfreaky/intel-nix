{
  llvm,
  cmake,
  ninja,
  fetchFromGitHub,
  oneTBB,
  opencl-headers,
  ocl-icd,
  gcc,
  lib,
}: let
  version = "3.9.1";
in
  llvm.stdenv.mkDerivation {
    pname = "onednn";
    inherit version;

    src = fetchFromGitHub {
      owner = "uxlfoundation";
      repo = "oneDNN";
      tag = "v${version}";
      hash = "sha256-DbLW22LgG8wrBNMsxoUGlacHLcfIBwqyiv+HOmFDtxc=";
    };

    nativeBuildInputs = [
      cmake
      ninja
    ];

    buildInputs = [
      oneTBB
      llvm.openmp
      #llvm.merged
      opencl-headers
      ocl-icd
      gcc
    ];

    # propagatedBuildInputs = [
    #   opencl-headers
    #   ocl-icd
    # ];

    # Fixup bad cmake paths
    postInstall = ''
      substituteInPlace $out/lib/cmake/dnnl/dnnl-config.cmake \
        --replace-fail "\''${PACKAGE_PREFIX_DIR}/" ""
    '';

    hardeningDisable = [
      "zerocallusedregs"
      "pacret"
      # NOTE: Only produces warnings, so could be re-enabled
      "shadowstack"
    ];

    cmakeFlags = [
      (lib.cmakeFeature "ONEDNN_CPU_RUNTIME" "SYCL")
      (lib.cmakeFeature "ONEDNN_GPU_RUNTIME" "SYCL")
    ];
  }
