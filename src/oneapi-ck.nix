{
  stdenv,
  cmake,
  ninja,
  python3,
  lib,
  zlib,
  lit,
  libffi,
  libxml2,
  spirv-tools,
  spirv-headers,
  opencl-headers,
  doxygen,
  fetchFromGitHub,
  llvmPackages_20,
  symlinkJoin,
}: let
  # version = "v4.0.0";
  version = "d0a32d701e34b3285de7ce776ea36abfec673df7";
  llvmPackages = llvmPackages_20;
  llvm-merged = symlinkJoin {
    name = "llvm-merged";
    paths = with llvmPackages; [
      llvm.dev
      clang-unwrapped.dev
      clang
      bintools
      clang-tools
    ];
  };
  # They currently use FetchContent for this and expect the actual source directory to be passed
  ocl-icd-loader = fetchFromGitHub {
    owner = "KhronosGroup";
    repo = "OpenCL-ICD-Loader";
    tag = "v2024.05.08";
    hash = "sha256-wFwc1ku3FNEH2k8TJij2sT7JspWorR/XbxXwPZaQcGA=";
  };
in
  stdenv.mkDerivation {
    pname = "oneapi-construction-kit";
    inherit version;

    src = fetchFromGitHub {
      owner = "uxlfoundation";
      repo = "oneapi-construction-kit";
      # tag = "v${version}";
      rev = "${version}";
      sha256 = "sha256-d0uwd5bF+qhTjX/chrjew91QHuGANekpEdHSjQUOYUA=";
    };

    nativeBuildInputs = [
      cmake
      ninja
      python3
      lit
      doxygen
      llvm-merged # for bintools
    ];

    buildInputs = [
      zlib
      spirv-tools
      spirv-headers
      libffi
      libxml2
      llvm-merged # for clang-tools
    ];

    cmakeFlags = [
      (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
      (lib.cmakeBool "FETCHCONTENT_QUIET" false)

      # (lib.cmakeFeature "CA_LLVM_INSTALL_DIR" "${llvm}")
      (lib.cmakeFeature "CA_LLVM_INSTALL_DIR" "${llvm-merged}")

      # This looks wrong, but only the include directories content is needed, so this is correct
      (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OPENCLHEADERS" "${opencl-headers}/include")

      (lib.cmakeFeature "CA_CL_EXTERNAL_ICD_LOADER_SOURCE_DIR" "${ocl-icd-loader}")
    ];
  }
