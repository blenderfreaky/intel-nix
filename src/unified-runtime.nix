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
  intel-compute-runtime,
  opencl-headers,
  ocl-icd,
  hdr-histogram,
  gtest,
  pkg-config,
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
  callPackage,
}: let
  version = "0.12.0";
  # TODO: intel-compute-runtime.src
  # compute-runtime = fetchFromGitHub {
  #   owner = "intel";
  #   repo = "compute-runtime";
  #   tag = "25.05.32567.17";
  #   sha256 = "sha256-/9UQJ5Ng2ip+3cNcVZOtKAmnx4LpmPja+aTghIqF1bc=";
  # };
  deps = callPackage ./llvm/deps.nix {};
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
    stdenv.mkDerivation (finalAttrs: {
      name = "unified-runtime";
      inherit version;

      nativeBuildInputs =
        [
          cmake
          ninja
          python3
        ]
        ++ lib.optionals levelZeroSupport [
          # Only needed to find level-zero
          pkg-config
        ];

      buildInputs =
        [
          unified-memory-framework
          zlib
          libbacktrace
          hwloc
          hdr-histogram # TODO: Make optional?
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
          intel-compute-runtime
        ]
        ++ lib.optionals vulkanSupport [
          vulkan-headers
          vulkan-loader
        ]
        ++ lib.optionals buildTests [
          gtest
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
        rev = "3bd57a2a8644daf484435ca9296e81410355d3ed";
        hash = "sha256-goJ5nqI79KwcFP9tq3++WhRAmhDZR5TMEdo6cs2NkEw=";
      };

      # src = fetchFromGitHub {
      #   owner = "intel";
      #   repo = "llvm";
      #   # tag = "sycl-web/sycl-latest-good";
      #   rev = "8959a5e5a6cebac8993c58c5597638b4510be91f";
      #   hash = "sha256-W+TpIeWlpkYpPI43lzI2J3mIIkzb9RtNTKy/0iQHyYI=";
      # };

      # sourceRoot = "${finalAttrs.src.name}/unified-runtime";

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
        # sed -i '/file(COPY / { /NO_SOURCE_PERMISSIONS/! s/)\s*$/ NO_SOURCE_PERMISSIONS)/ }' cmake/FetchLevelZero.cmake
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

          (lib.cmakeBool "UR_ENABLE_LATENCY_HISTOGRAM" true)

          # (lib.cmakeBool "UR_COMPUTE_RUNTIME_FETCH_REPO" false)
          # (lib.cmakeFeature "UR_COMPUTE_RUNTIME_REPO" "${compute-runtime}")

          (lib.cmakeBool "UR_BUILD_EXAMPLES" buildTests)
          (lib.cmakeBool "UR_BUILD_TESTS" buildTests)

          (lib.cmakeBool "UR_BUILD_ADAPTER_L0" levelZeroSupport)
          (lib.cmakeBool "UR_BUILD_ADAPTER_L0_V2" levelZeroSupport)
          (lib.cmakeBool "UR_BUILD_ADAPTER_OPENCL" openclSupport)
          (lib.cmakeBool "UR_BUILD_ADAPTER_CUDA" cudaSupport)
          (lib.cmakeBool "UR_BUILD_ADAPTER_HIP" rocmSupport)
          (lib.cmakeBool "UR_BUILD_ADAPTER_NATIVE_CPU" nativeCpuSupport)
          # (lib.cmakeBool "UR_BUILD_ADAPTER_ALL" false)

          (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-HEADERS" "${deps.opencl-headers}")
          (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-ICD" "${deps.opencl-icd-loader}")
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
          # ]
          # ++ lib.optionals levelZeroSupport [
          #   (lib.cmakeFeature "UR_LEVEL_ZERO_INCLUDE_DIR" "${lib.getInclude level-zero}/include/level_zero")
          #   (lib.cmakeFeature "UR_LEVEL_ZERO_LOADER_LIBRARY" "${lib.getLib level-zero}/lib/libze_loader.so")
          # ]
          # ++ lib.optionals buildTests [
          #   (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_GOOGLETEST" "${gtest}")
        ];

      passthru = {
        tests = make true;
        backends =
          lib.optionals cudaSupport [
            "cuda"
          ]
          ++ lib.optionals rocmSupport [
            "hip"
          ]
          ++ lib.optionals levelZeroSupport [
            "level_zero"
            "level_zero_v2"
          ];
      };
    });
in
  make buildTests
