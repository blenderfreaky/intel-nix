{
  stdenv,
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
  lit,
  filecheck,
  ctestCheckHook,
  intel-llvm-src,
  levelZeroSupport ? true,
  openclSupport ? true,
  # Broken
  cudaSupport ? false,
  rocmSupport ? false,
  rocmGpuTargets ? builtins.concatStringsSep ";" rocmPackages.clr.gpuTargets,
  nativeCpuSupport ? false,
}: let
  version = "0.12.0";
  rocmtoolkit_joined = symlinkJoin {
    name = "rocm-merged";

    # The packages in here were chosen pretty arbitrarily.
    # clr and comgr are definitely needed though.
    paths = with rocmPackages; [
      clr
      rocm-comgr
      hsakmt
    ];
  };
in
  stdenv.mkDerivation (finalAttrs: {
    name = "unified-runtime";
    inherit version;

    src = intel-llvm-src;
    sourceRoot = "source/unified-runtime";

    # Tests are disabled because many require UR_DPCXX (Intel DPC++ compiler)
    # which is not available in this build
    doCheck = false;

    nativeBuildInputs = [
      cmake
      ninja
      python3
      pkg-config
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
      ]
      ++ lib.optionals levelZeroSupport [
        level-zero
        intel-compute-runtime
      ]
      # ++ lib.optionals vulkanSupport [
      #   vulkan-headers
      #   vulkan-loader
      # ]
      ++ lib.optionals finalAttrs.doCheck [
        gtest
        lit
        filecheck
      ];

    # Without this it fails to link to hwloc, despite it being in the buildInputs
    NIX_LDFLAGS = "-lhwloc";

    nativeCheckInputs = lib.optionals finalAttrs.doCheck [
      ctestCheckHook
    ];

    postPatch = ''
      # `NO_CMAKE_PACKAGE_REGISTRY` prevents it from finding OpenCL, so we unset it
      substituteInPlace cmake/FetchOpenCL.cmake \
        --replace-fail "NO_CMAKE_PACKAGE_REGISTRY" ""
    '';

    cmakeFlags =
      [
        (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
        (lib.cmakeBool "FETCHCONTENT_QUIET" false)

        # Currently broken
        (lib.cmakeBool "UR_ENABLE_LATENCY_HISTOGRAM" false)

        (lib.cmakeBool "UR_BUILD_EXAMPLES" finalAttrs.doCheck)
        (lib.cmakeBool "UR_BUILD_TESTS" finalAttrs.doCheck)

        (lib.cmakeBool "UR_BUILD_ADAPTER_L0" levelZeroSupport)
        (lib.cmakeBool "UR_BUILD_ADAPTER_L0_V2" levelZeroSupport)
        (lib.cmakeBool "UR_BUILD_ADAPTER_OPENCL" openclSupport)
        (lib.cmakeBool "UR_BUILD_ADAPTER_CUDA" cudaSupport)
        (lib.cmakeBool "UR_BUILD_ADAPTER_HIP" rocmSupport)
        (lib.cmakeBool "UR_BUILD_ADAPTER_NATIVE_CPU" nativeCpuSupport)
        # (lib.cmakeBool "UR_BUILD_ADAPTER_ALL" false)
      ]
      ++ lib.optionals rocmSupport [
        (lib.cmakeFeature "UR_HIP_ROCM_DIR" "${rocmtoolkit_joined}")
        (lib.cmakeFeature "AMDGPU_TARGETS" rocmGpuTargets)
      ];

    passthru = {
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
  })
