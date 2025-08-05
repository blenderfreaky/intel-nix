{
  stdenv,
  fetchFromGitHub,
  lib,
  cmake,
  ninja,
  level-zero,
  hwloc,
  # jemalloc,
  autogen,
  autoconf,
  automake,
  oneTBB,
  numactl,
  pkg-config,
  cudaPackages,
  useJemalloc ? false,
  cudaSupport ? false,
  levelZeroSupport ? true,
  ctestCheckHook,
  buildTests ? false,
  python3,
  doxygen,
  sphinx,
  buildDocs ? true,
}: let
  version = "1.0.0";
  tag = "v${version}";
  gtest = fetchFromGitHub {
    owner = "google";
    repo = "googletest";
    tag = "v1.15.2";
    sha256 = "sha256-1OJ2SeSscRBNr7zZ/a8bJGIqAnhkg45re0j3DtPfcXM=";
  };
  gbench = fetchFromGitHub {
    owner = "google";
    repo = "benchmark";
    tag = "v1.9.0";
    sha256 = "sha256-5cl1PIjhXaL58kSyWZXRWLq6BITS2BwEovPhwvk2e18=";
  };
  jemalloc = fetchFromGitHub {
    owner = "jemalloc";
    repo = "jemalloc";
    tag = "5.3.0";
    sha256 = "sha256-bb0OhZVXyvN+hf9BpPSykn5cGm87a0C+Y/iXKt9wTSs=";
  };
in
  stdenv.mkDerivation (finalAttrs: {
    name = "unified-memory-framework";
    inherit version;

    nativeBuildInputs =
      [
        cmake
        ninja
        pkg-config
      ]
      ++ lib.optionals buildDocs [
        python3
        doxygen
        sphinx
      ];

    buildInputs =
      [
        level-zero
        oneTBB
        hwloc
        hwloc.dev
      ]
      ++ lib.optionals useJemalloc [
        jemalloc
        autogen
        autoconf
        automake
      ]
      ++ lib.optionals cudaSupport [
        cudaPackages.cuda_cudart
      ]
      ++ lib.optionals buildTests [
        numactl
      ];

    # TODO: Is this needed?
    nativeCheckInputs = lib.optionals buildTests [
      ctestCheckHook
    ];

    src = fetchFromGitHub {
      owner = "oneapi-src";
      repo = "unified-memory-framework";
      inherit tag;
      sha256 = "sha256-nolnyxnupHDzz92/uFpIJsmEkcvD9MgI0oMX0V8aM1s=";
    };

    postPatch =
      ''
        # The CMake tries to find out the version via git.
        # Since we're not in a clone, git describe won't work.
        substituteInPlace cmake/helpers.cmake \
          --replace-fail "git describe --always" "echo ${tag}"
      ''
      + (lib.optionalString useJemalloc ''
        # This fixes building with ninja
        # See https://github.com/oneapi-src/unified-memory-framework/issues/1474
        substituteInPlace CMakeLists.txt \
          --replace-fail "\$(nproc)" "\$\$(nproc)"
      '');

    cmakeFlags =
      [
        (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
        (lib.cmakeBool "FETCHCONTENT_QUIET" false)

        (lib.cmakeBool "UMF_BUILD_CUDA_PROVIDER" cudaSupport)
        (lib.cmakeBool "UMF_BUILD_LEVEL_ZERO_PROVIDER" levelZeroSupport)

        (lib.cmakeBool "UMF_BUILD_LIBUMF_POOL_JEMALLOC" useJemalloc)

        (lib.cmakeBool "UMF_BUILD_TESTS" buildTests)
        (lib.cmakeBool "UMF_BUILD_GPU_TESTS" buildTests)
        (lib.cmakeBool "UMF_BUILD_BENCHMARKS" buildTests)
        (lib.cmakeBool "UMF_BUILD_EXAMPLES" buildTests)
        (lib.cmakeBool "UMF_BUILD_GPU_EXAMPLES" buildTests)

        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_JEMALLOC_TARG" "${jemalloc}")
      ]
      ++ lib.optionals buildTests [
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_GOOGLETEST" "${gtest}")
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_GOOGLEBENCHMARK" "${gbench}")
      ];

    NIX_LDFLAGS = lib.optionalString buildTests "-rpath ${
      lib.makeLibraryPath [
        oneTBB
        level-zero
      ]
      ++ lib.optionals useJemalloc [
        jemalloc
      ]
    }";

    doCheck = buildTests;
  })
