{
  lib,
  # stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  python3,
  pkg-config,
  zstd,
  hwloc,
  valgrind,
  # We use the in-tree unified-runtime, but we need all the same flags as the out-of-tree version.
  # Rather than duplicating the flags, we can simply use the existing flags.
  # We can also use this to debug unified-runtime without building the entire LLVM project.
  unified-runtime,
  emhash,
  sphinx,
  doxygen,
  level-zero,
  libcxx,
  libxml2,
  libedit,
  llvmPackages_21,
  callPackage,
  parallel-hashmap,
  spirv-headers,
  spirv-tools,
  fetchpatch,
  # opencl-headers,
  # emhash,
  zlib,
  wrapCC,
  ctestCheckHook,
  rocmPackages ? {},
  levelZeroSupport ? true,
  openclSupport ? true,
  # Broken
  cudaSupport ? false,
  rocmSupport ? true,
  rocmGpuTargets ? builtins.concatStringsSep ";" rocmPackages.clr.gpuTargets,
  nativeCpuSupport ? false,
  vulkanSupport ? true,
  useLibcxx ? false,
  useLld ? false,
  buildTests ? false,
  buildDocs ? false,
  buildMan ? false,
}: let
  version = "unstable-2025-08-21";
  date = "20250821";
  stdenv =
    if useLibcxx
    then llvmPackages_21.libcxxStdenv
    else llvmPackages_21.stdenv;
  deps = callPackage ./deps.nix {};
  unified-runtime' = unified-runtime.override {
    inherit
      levelZeroSupport
      openclSupport
      cudaSupport
      rocmSupport
      rocmGpuTargets
      nativeCpuSupport
      vulkanSupport
      buildTests
      ;
  };
  # See the postPatch phase for details on why this is used
  ccWrapperStub = wrapCC (
    stdenv.mkDerivation {
      name = "ccWrapperStub";
      dontUnpack = true;
      installPhase = let
        root = "/build/source/build";
      in ''
        mkdir -p $out/bin
        cat > $out/bin/clang++ <<EOF
        #!/bin/sh
        exec "${root}/bin/clang-21" "\$@"
        EOF
        chmod +x $out/bin/clang++
      '';
      passthru.isClang = true;
    }
  );
in
  stdenv.mkDerivation {
    pname = "intel-llvm";
    inherit version;

    src = fetchFromGitHub {
      owner = "intel";
      repo = "llvm";
      # tag = "v${version}";
      rev = "64928c5154d7a0d8b5f03e7771ce7411d14fea20";
      hash = "sha256-WTxZre8cpOQjR2K8TX3ygZxn5Math0ofs+l499RsgsI=";
    };

    # I'd like to split outputs, but currently this fails
    # outputs = [
    #   "out"
    #   "lib"
    #   "dev"
    #   "rsrc"
    # ];

    nativeBuildInputs =
      [
        cmake
        ninja
        python3
        pkg-config
        zlib
      ]
      ++ lib.optionals useLld [
        llvmPackages_21.bintools
      ];

    buildInputs =
      [
        sphinx
        doxygen
        spirv-tools
        libxml2
        valgrind.dev
        hwloc
        emhash
      ]
      ++ lib.optionals useLibcxx [
        libcxx
        libcxx.dev
      ]
      ++ unified-runtime'.buildInputs;

    propagatedBuildInputs = [
      zstd
      zlib
      libedit
    ];

    # TODO: Is this needed?
    nativeCheckInputs = lib.optionals buildTests [
      ctestCheckHook
    ];

    patches = [
      (fetchpatch {
        name = "make-sycl-version-reproducible";
        url = "https://github.com/intel/llvm/commit/1c22570828e24a628c399aae09ce15ad82b924c6.patch";
        hash = "sha256-leBTUmanYaeoNbmA0m9VFX/5ViACuXidWUhohewshQQ=";
      })
    ];

    postPatch = ''
      # Parts of libdevice are built using the freshly-built compiler.
      # As it tries to link to system libraries, we need to wrap it with the
      # usual nix cc-wrapper.
      # Since the compiler to be wrapped is not available at this point,
      # we use a stub that points to where it will be later on
      # in `/build/source/build/bin/clang-21`
      # Note: both nix and bash try to expand clang_exe here, so double-escape it
      substituteInPlace libdevice/cmake/modules/SYCLLibdevice.cmake \
        --replace-fail "\''${clang_exe}" "${ccWrapperStub}/bin/clang++"

      # When running without this, their CMake code copies files from the Nix store.
      # As the Nix store is read-only and COPY copies permissions by default,
      # this will lead to the copied files also being read-only.
      # As CMake at a later point wants to write into copied folders, this causes
      # the build to fail with a (rather cryptic) permission error.
      # By setting NO_SOURCE_PERMISSIONS we side-step this issue.
      # Note in case of future build failures: if there are executables in any of the copied folders,
      # we may need to add special handling to set the executable permissions.
      # See also: https://github.com/intel/llvm/issues/19635#issuecomment-3134830708
      sed -i '/file(COPY / { /NO_SOURCE_PERMISSIONS/! s/)\s*$/ NO_SOURCE_PERMISSIONS)/ }' \
        unified-runtime/cmake/FetchLevelZero.cmake \
        sycl/CMakeLists.txt \
        sycl/cmake/modules/FetchEmhash.cmake

      pushd unified-runtime
      chmod -R u+w .
      patch -p1 < ${./patches/unified-runtime.patch}
      patch -p1 < ${./patches/unified-runtime-2.patch}
      popd
    '';

    preConfigure = ''
      flags=$(python buildbot/configure.py \
          --print-cmake-flags \
          -t Release \
          --docs \
          --cmake-gen Ninja \
          ${lib.optionalString cudaSupport "--cuda"} \
          ${lib.optionalString rocmSupport "--hip"} \
          ${lib.optionalString nativeCpuSupport "--native_cpu"} \
          ${lib.optionalString useLibcxx "--use-libcxx"} \
          ${lib.optionalString useLibcxx "--libcxx-include ${lib.getInclude libcxx}/include"} \
          ${lib.optionalString useLibcxx "--libcxx-library ${lib.getLib libcxx}/lib"} \
          ${lib.optionalString useLld "--use-lld"} \
          ${lib.optionalString levelZeroSupport "--level_zero_adapter_version V1"} \
          ${lib.optionalString levelZeroSupport "--l0-headers ${lib.getInclude level-zero}/include/level_zero"} \
          ${lib.optionalString levelZeroSupport "--l0-loader ${lib.getLib level-zero}/lib/libze_loader.so"} \
          # --enable-all-llvm-targets
          # --shared-libs # Bad and should not be used
      )

      # We eval because flags is separated as shell-escaped strings.
      # We can't just split by space because it may contain escaped spaces,
      # so we just let bash handle it.
      # TODO: This may not be necessary
      # NOTE: We prepend, so that flags we set manually override what the build script does.
      eval "prependToVar cmakeFlags $flags"

      # Remove the install prefix flag
      cmakeFlags=(''${cmakeFlags[@]/-DCMAKE_INSTALL_PREFIX=\/build\/source\/build\/install})

      cmakeFlagsArray+=(
      "-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG -march=skylake -mtune=znver3 -flto=thin -ffat-lto-objects"
      "-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG -march=skylake -mtune=znver3 -flto=thin -ffat-lto-objects"
      )
    '';

    cmakeDir = "/build/source/llvm";

    cmakeFlags =
      [
        # (lib.cmakeFeature "LLVM_TARGETS_TO_BUILD" (lib.concatStringsSep ";" llvmTargetsToBuild'))
        # (lib.cmakeFeature "LLVM_ENABLE_PROJECTS" (lib.concatStringsSep ";" llvmProjectsToBuild))
        (lib.cmakeFeature "LLVM_HOST_TRIPLE" stdenv.hostPlatform.config)
        (lib.cmakeFeature "LLVM_DEFAULT_TARGET_TRIPLE" stdenv.hostPlatform.config)
        (lib.cmakeBool "LLVM_INSTALL_UTILS" true)
        (lib.cmakeBool "LLVM_INCLUDE_DOCS" (buildDocs || buildMan))
        (lib.cmakeBool "MLIR_INCLUDE_DOCS" (buildDocs || buildMan))
        (lib.cmakeBool "LLVM_BUILD_DOCS" (buildDocs || buildMan))
        # # Way too slow, only uses one core
        # # (lib.cmakeBool "LLVM_ENABLE_DOXYGEN" (buildDocs || buildMan))
        (lib.cmakeBool "LLVM_ENABLE_SPHINX" (buildDocs || buildMan))
        (lib.cmakeBool "SPHINX_OUTPUT_HTML" buildDocs)
        (lib.cmakeBool "SPHINX_OUTPUT_MAN" buildMan)
        # (lib.cmakeBool "SPHINX_WARNINGS_AS_ERRORS" false)
        (lib.cmakeBool "LLVM_BUILD_TESTS" buildTests)
        (lib.cmakeBool "LLVM_INCLUDE_TESTS" buildTests)
        (lib.cmakeBool "MLIR_INCLUDE_TESTS" buildTests)
        (lib.cmakeBool "SYCL_INCLUDE_TESTS" buildTests)

        "-DCMAKE_BUILD_TYPE=Release"
        # "-DLLVM_ENABLE_ZSTD=FORCE_ON"
        # TODO
        # "-DLLVM_ENABLE_ZLIB=FORCE_ON"
        "-DLLVM_ENABLE_THREADS=ON"
        # Breaks tablegen build somehow
        # "-DLLVM_ENABLE_LTO=Thin"
        # "-DLLVM_USE_STATIC_ZSTD=OFF"

        (lib.cmakeBool "BUILD_SHARED_LIBS" false)
        # # TODO: configure fails when these are true, but I've no idea why
        # NOTE: Fails with buildbot/configure.py as well when these are set
        (lib.cmakeBool "LLVM_LINK_LLVM_DYLIB" false)
        (lib.cmakeBool "LLVM_BUILD_LLVM_DYLIB" false)

        (lib.cmakeBool "LLVM_ENABLE_LIBCXX" useLibcxx)
        (lib.cmakeFeature "CLANG_DEFAULT_CXX_STDLIB" (
          if useLibcxx
          then "libc++"
          else "libstdc++"
        ))

        (lib.cmakeFeature "SYCL_COMPILER_VERSION" date)

        (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
        (lib.cmakeBool "FETCHCONTENT_QUIET" false)

        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_VC-INTRINSICS" "${deps.vc-intrinsics}")

        (lib.cmakeFeature "LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR" "${spirv-headers.src}")

        # These can be switched over to nixpkgs versions once they're updated
        # See: https://github.com/NixOS/nixpkgs/pull/428558
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-HEADERS" "${deps.opencl-headers}")
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-ICD" "${deps.opencl-icd-loader}")

        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_ONEAPI-CK" "${deps.oneapi-ck}")

        # Lookup broken
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_EMHASH" "${deps.emhash}")
        # Lookup not implemented
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_PARALLEL-HASHMAP" "${parallel-hashmap.src}")
      ]
      ++ lib.optional useLld (lib.cmakeFeature "LLVM_USE_LINKER" "lld")
      ++ unified-runtime'.cmakeFlags;

    # This hardening option causes compilation errors when compiling for amdgcn, spirv and others
    # TODO: Can the cc wrapper be made aware of this somehow?
    hardeningDisable = ["zerocallusedregs"];

    # TODO: Investigate why this is needed
    NIX_LDFLAGS = "-lhwloc";

    requiredSystemFeatures = ["big-parallel"];
    enableParallelBuilding = true;

    doCheck = true;

    meta = with lib; {
      description = "Intel LLVM-based compiler with SYCL support";
      longDescription = ''
        Intel's LLVM-based compiler toolchain with Data Parallel C++ (DPC++)
        and SYCL support for heterogeneous computing across CPUs, GPUs, and FPGAs.
      '';
      homepage = "https://github.com/intel/llvm";
      # TODO: Apache with LLVM exceptions
      # license = with licenses; [ ncsa ];
      maintainers = with maintainers; [blenderfreaky];
      platforms = platforms.linux;
    };

    passthru = {
      isClang = true;
      # The llvm package set of the same version as
      # Intels compiler is based on
      baseLlvm = llvmPackages_21;
    };
  }
