{
  stdenv,
  fetchFromGitHub,
  lib,
  cmake,
  ninja,
  unified-memory-framework,
  zlib,
  libbacktrace,
  hwloc,
  python3,
  symlinkJoin,
  rocmPackages ? {},
  cudaPackages ? {},
  vulkan-headers,
  vulkan-loader,
  autoAddDriverRunpath,
  level-zero,
  opencl-headers,
  ocl-icd,
  levelZeroSupport ? true,
  openclSupport ? true,
  # Broken
  cudaSupport ? false,
  rocmSupport ? true,
  rocmGpuTargets ? builtins.concatStringsSep ";" rocmPackages.clr.gpuTargets,
  vulkanSupport ? true,
  nativeCpuSupport ? true,
  buildTests ? false,
  lit,
  filecheck,
  ctestCheckHook,
}: let
  version = "0.12.0";
  gtest = fetchFromGitHub {
    owner = "google";
    repo = "googletest";
    tag = "v1.15.2";
    sha256 = "sha256-1OJ2SeSscRBNr7zZ/a8bJGIqAnhkg45re0j3DtPfcXM=";
  };
  compute-runtime = fetchFromGitHub {
    owner = "intel";
    repo = "compute-runtime";
    tag = "25.05.32567.17";
    sha256 = "sha256-/9UQJ5Ng2ip+3cNcVZOtKAmnx4LpmPja+aTghIqF1bc=";
  };
  hdr-histogram = fetchFromGitHub {
    owner = "HdrHistogram";
    repo = "HdrHistogram_c";
    tag = "0.11.8";
    sha256 = "sha256-TFlrC4bgK8o5KRZcLMlYU5EO9Oqaqe08PjJgmsUl51M=";
  };
  rocmtoolkit_joined = symlinkJoin {
    name = "rocm-merged";

    # The packages in here were chosen pretty arbitrarily.
    # clr and comgr are definitely needed though.
    paths = with rocmPackages; [
      rocmPath
      rocm-comgr
      hsakmt
    ];
  };

  make = buildTests:
    stdenv.mkDerivation {
      name = "unified-runtime";
      inherit version;

      nativeBuildInputs = [
        cmake
        ninja
        python3
      ];

      buildInputs =
        [
          unified-memory-framework
          zlib
          libbacktrace
          hwloc
        ]
        ++ lib.optionals openclSupport [
          opencl-headers
          ocl-icd
        ]
        ++ lib.optionals rocmSupport [
          rocmtoolkit_joined
          # rocmPackages.rocmPath
          # rocmPackages.hsakmt
        ]
        ++ lib.optionals cudaSupport [
          cudaPackages.cuda_cudart
          autoAddDriverRunpath
        ]
        ++ lib.optionals levelZeroSupport [
          level-zero
        ]
        ++ lib.optionals vulkanSupport [
          vulkan-headers
          vulkan-loader
        ]
        ++ lib.optionals buildTests [
          lit
          filecheck
        ];

      src = fetchFromGitHub {
        owner = "oneapi-src";
        repo = "unified-runtime";
        # tag = "v${version}";
        # TODO: Update to a tag once a new release is available
        #       On current latest tag there's build issues that are resolved in later commits,
        #       so we use a newer commit for now.
        rev = "a6437589c67c3acdeffa80a0d544a6612e63a29b";
        sha256 = "sha256-zMZc0sy+waqcGyGVu+T0/+ZSpH8oHcQzNp1B3MNUopI=";
      };

      nativeCheckInputs = lib.optionals buildTests [
        ctestCheckHook
      ];

      postPatch = ''
        # The latter is used everywhere except this one file. For some reason,
        # the former is not set, at least when building with Nix, so we replace it.
        substituteInPlace cmake/helpers.cmake \
          --replace-fail "PYTHON_EXECUTABLE" "Python3_EXECUTABLE"

        # If we let it copy with default settings, it'll copy the permissions of the source files.
        # As the source files of level zero point to the nix store, those permissions will make it non-writable.
        # The build will try to write new files into directories that are now read-only.
        # To avoid this, we set NO_SOURCE_PERMISSIONS.
        sed -i '/file(COPY / { /NO_SOURCE_PERMISSIONS/! s/)\s*$/ NO_SOURCE_PERMISSIONS)/ }' cmake/FetchLevelZero.cmake
      '';

      # preConfigure = ''
      #   # For some reason, it doesn't create this on its own,
      #   # causing a cryptic Permission denied error.
      #   mkdir -p /build/source/build/source/common/level_zero_loader/level_zero
      # '';

      cmakeFlags =
        [
          (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
          (lib.cmakeBool "FETCHCONTENT_QUIET" false)

          (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_HDR_HISTOGRAM" "${hdr-histogram}")

          # Their CMake code will print that it's fetching from/will download from github anyways.
          # This can be safely ignored - it's not actually doing that.
          (lib.cmakeBool "UR_USE_EXTERNAL_UMF" true)

          (lib.cmakeBool "UR_ENABLE_LATENCY_HISTOGRAM" false)
          # (lib.cmakeBool "UR_ENABLE_LATENCY_HISTOGRAM" true)

          (lib.cmakeBool "UR_COMPUTE_RUNTIME_FETCH_REPO" false)
          (lib.cmakeFeature "UR_COMPUTE_RUNTIME_REPO" "${compute-runtime}")

          (lib.cmakeBool "UR_BUILD_EXAMPLES" buildTests)
          (lib.cmakeBool "UR_BUILD_TESTS" buildTests)

          (lib.cmakeBool "UR_BUILD_ADAPTER_L0" levelZeroSupport)
          (lib.cmakeBool "UR_BUILD_ADAPTER_L0_V2" levelZeroSupport)
          (lib.cmakeBool "UR_BUILD_ADAPTER_OPENCL" openclSupport)
          (lib.cmakeBool "UR_BUILD_ADAPTER_CUDA" cudaSupport)
          (lib.cmakeBool "UR_BUILD_ADAPTER_HIP" rocmSupport)
          (lib.cmakeBool "UR_BUILD_ADAPTER_NATIVE_CPU" nativeCpuSupport)
          # (lib.cmakeBool "UR_BUILD_ADAPTER_ALL" false)
        ]
        ++ lib.optionals cudaSupport [
          (lib.cmakeFeature "CUDA_TOOLKIT_ROOT_DIR" "${cudaPackages.cudatoolkit}")
          (lib.cmakeFeature "CUDAToolkit_ROOT" "${cudaPackages.cudatoolkit}")
          (lib.cmakeFeature "CUDAToolkit_INCLUDE_DIRS" "${cudaPackages.cudatoolkit}/include/")
          (lib.cmakeFeature "CUDA_cuda_driver_LIBRARY" "${cudaPackages.cudatoolkit}/lib/")
        ]
        ++ lib.optionals rocmSupport [
          (lib.cmakeFeature "UR_HIP_ROCM_DIR" "${rocmtoolkit_joined}")
          # (lib.cmakeFeature "UR_HIP_ROCM_DIR" "${rocmPackages.rocmPath}")
          (lib.cmakeFeature "AMDGPU_TARGETS" rocmGpuTargets)
        ]
        ++ lib.optionals levelZeroSupport [
          (lib.cmakeFeature "UR_LEVEL_ZERO_INCLUDE_DIR" "${lib.getInclude level-zero}/include/level_zero")
          (lib.cmakeFeature "UR_LEVEL_ZERO_LOADER_LIBRARY" "${lib.getLib level-zero}/lib/libze_loader.so")
        ]
        ++ lib.optionals buildTests [
          (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_GOOGLETEST" "${gtest}")
        ];

      passthru.tests = make true;
    };
in
  make buildTests
