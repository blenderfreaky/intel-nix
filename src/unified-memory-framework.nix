{
  stdenv,
  fetchFromGitHub,
  fetchpatch,
  lib,
  cmake,
  ninja,
  level-zero,
  hwloc,
  autogen,
  autoconf,
  automake,
  oneTBB,
  numactl,
  pkg-config,
  cudaPackages,
  useJemalloc ? true,
  cudaSupport ? false,
  levelZeroSupport ? true,
  ctestCheckHook,
  buildTests ? false,
  gtest,
  gbenchmark,
  python3,
  doxygen,
  sphinx,
  buildDocs ? true,
}: let
  version = "1.0.1";
  tag = "v${version}";
  # This needs to be vendored, as they don't support using a pre-built version
  # and they compile with specific flags that the nixpkgs version doesn't (and shouldn't) set
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
        # Is this always needed?
        level-zero
        oneTBB
        # TODO: Are these both needed?
        # Also, should they be propagated?
        hwloc
        hwloc.dev
      ]
      ++ lib.optionals useJemalloc [
        jemalloc
        # TODO: Are these needed?
        autogen
        autoconf
        automake
      ]
      ++ lib.optionals cudaSupport [
        cudaPackages.cuda_cudart
      ]
      ++ lib.optionals finalAttrs.doCheck [
        numactl
        gtest
        gbenchmark
      ];

    # TODO: Is this needed?
    nativeCheckInputs = lib.optionals finalAttrs.doCheck [
      ctestCheckHook
    ];

    src = fetchFromGitHub {
      owner = "oneapi-src";
      repo = "unified-memory-framework";
      inherit tag;
      sha256 = "sha256-aS03kZDVh/TEjKialuV5/i7C65OddAKOda22ik7ZrPs=";
    };

    patches = [
      (fetchpatch {
        url = "https://github.com/oneapi-src/unified-memory-framework/commit/df9fcf13eefd804110d5cc4cbc661ec21febb7c7.patch";
        hash = "sha256-g1Sir5S7zeIFqkQYMeLVpdbJjXvlWN69rEZu4qTwr9w=";
      })
    ];

    postPatch = ''
      # The CMake tries to find out the version via git.
      # Since we're not in a clone, git describe won't work.
      substituteInPlace cmake/helpers.cmake \
        --replace-fail "git describe --always" "echo ${tag}"
    '';

    # Autoconf wants to write files, so we copy the source to the build directory
    # where we can make it writable
    preConfigure = lib.optionalString useJemalloc ''
      cp -r ${jemalloc} /build/jemalloc
      chmod -R u+w /build/jemalloc
    '';

    cmakeFlags = [
      (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
      (lib.cmakeBool "FETCHCONTENT_QUIET" false)

      (lib.cmakeBool "UMF_BUILD_CUDA_PROVIDER" cudaSupport)
      (lib.cmakeBool "UMF_BUILD_LEVEL_ZERO_PROVIDER" levelZeroSupport)

      (lib.cmakeBool "UMF_BUILD_LIBUMF_POOL_JEMALLOC" useJemalloc)

      (lib.cmakeBool "UMF_BUILD_TESTS" finalAttrs.doCheck)
      (lib.cmakeBool "UMF_BUILD_GPU_TESTS" finalAttrs.doCheck)
      (lib.cmakeBool "UMF_BUILD_BENCHMARKS" finalAttrs.doCheck)
      (lib.cmakeBool "UMF_BUILD_EXAMPLES" finalAttrs.doCheck)
      (lib.cmakeBool "UMF_BUILD_GPU_EXAMPLES" finalAttrs.doCheck)

      (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_JEMALLOC_TARG" "/build/jemalloc")
      (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_GOOGLETEST" "${gtest.src}")
    ];

    doCheck = buildTests;

    NIX_LDFLAGS = lib.optionalString finalAttrs.doCheck "-rpath ${
      lib.makeLibraryPath [
        oneTBB
        level-zero
      ]
    }";
  })
