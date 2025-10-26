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
  hdrhistogram_c,
  gtest,
  pkg-config,
  levelZeroSupport ? true,
  # I don't think this can be off, so remove?
  openclSupport ? true,
  # Broken
  cudaSupport ? false,
  rocmSupport ? false,
  rocmGpuTargets ? builtins.concatStringsSep ";" rocmPackages.clr.gpuTargets,
  # I don't think this can be off, so remove?
  vulkanSupport ? true,
  nativeCpuSupport ? false,
  buildTests ? false,
  lit,
  filecheck,
  ctestCheckHook,
  callPackage,
}: let
  version = "0.12.0";
  deps = callPackage ./llvm/deps.nix {};
  rocmtoolkit_joined = symlinkJoin {
    name = "rocm-merged";

    # The packages in here were chosen pretty arbitrarily.
    # clr and comgr are definitely needed though.
    paths = with rocmPackages; [
      # rocmPath
      clr
      rocm-comgr
      hsakmt
    ];
  };

  cudaComponents = with cudaPackages; [
    (cuda_nvcc.__spliced.buildHost or cuda_nvcc)
    (cuda_nvprune.__spliced.buildHost or cuda_nvprune)
    cuda_cccl # block_load.cuh
    cuda_cudart # cuda.h
    cuda_cupti # cupti.h
    cuda_nvcc # See https://github.com/google/jax/issues/
    cuda_nvml_dev # nvml.h
    cuda_nvtx # nvToolsExt.h
    libcublas # cublas_api.h
    libcufft # cufft.h
    libcurand # curand.h
    libcusolver # cusolver_common.h
    libcusparse # cusparse.h
  ];

  cudatoolkitDevMerged =
    symlinkJoin {
      name = "cuda-${cudaPackages.cudaMajorMinorVersion}-de
v-merged";
      paths =
        lib.concatMap (p: [
          (lib.getBin p)
          (lib.getDev p)
          (lib.getLib p)
          (lib.getOutput "static" p) # Makes for a very fat closure
        ])
        cudaComponents;
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
          pkg-config
        ]
        ++ lib.optionals cudaSupport [
          #cudatoolkitDevMerged
        ];

      buildInputs =
        [
          unified-memory-framework
          zlib
          libbacktrace
          hwloc
          hdrhistogram_c
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
          #cudatoolkitDevMerged
          #cudaPackages.cuda_cudart
          #cudaPackages.cuda_nvcc
          #cudaPackages.cuda_cccl
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
        rev = "460ab7bc648fa2b3be8e0b7b4f0fd237db5fb606";
        hash = "sha256-aPoCFsLla3jUR1v/cNEjHvRWpks/P5BZ6DQ59+vUvcQ=";
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

      patches = [
        #./llvm/unified-runtime.patch
        #./llvm/unified-runtime-2.patch
      ];

      postPatch = ''
        # `NO_CMAKE_PACKAGE_REGISTRY` prevents it from finding OpenCL, so we unset it
        substituteInPlace cmake/FetchOpenCL.cmake \
          --replace-fail "NO_CMAKE_PACKAGE_REGISTRY" ""
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

          # Currently broken
          (lib.cmakeBool "UR_ENABLE_LATENCY_HISTOGRAM" false)

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

          # (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-HEADERS" "${deps.opencl-headers}")
          # (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-ICD" "${deps.opencl-icd-loader}")
        ]
        ++ lib.optionals cudaSupport [
          # (lib.cmakeFeature "CUDA_TOOLKIT_ROOT_DIR" "${cudaPackages.cudatoolkit}")
          (lib.cmakeFeature "CUDAToolkit_ROOT" "${cudatoolkitDevMerged}")
          # (lib.cmakeFeature "CUDAToolkit_INCLUDE_DIRS" "${cudaPackages.cudatoolkit}/include/")
          # (lib.cmakeFeature "CUDA_cuda_driver_LIBRARY" "${cudaPackages.cudatoolkit}/lib/")
        ]
        ++ lib.optionals rocmSupport [
          (lib.cmakeFeature "UR_HIP_ROCM_DIR" "${rocmtoolkit_joined}")
          # (lib.cmakeFeature "UR_HIP_ROCM_DIR" "${rocmPackages.rocmPath}")
          (lib.cmakeFeature "AMDGPU_TARGETS" rocmGpuTargets)
        ]
        ++ lib.optionals levelZeroSupport [
          # (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_exp-headers" "${deps.compute-runtime}")

          #   (lib.cmakeFeature "UR_LEVEL_ZERO_INCLUDE_DIR" "${lib.getInclude level-zero}/include/level_zero")
          #   (lib.cmakeFeature "UR_LEVEL_ZERO_LOADER_LIBRARY" "${lib.getLib level-zero}/lib/libze_loader.so")
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
