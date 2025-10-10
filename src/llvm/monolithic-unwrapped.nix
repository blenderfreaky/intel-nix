{
  lib,
  stdenv,
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
  vc-intrinsics,
  emhash,
  sphinx,
  doxygen,
  level-zero,
  libxml2,
  libedit,
  llvmPackages_21,
  callPackage,
  parallel-hashmap,
  spirv-headers,
  spirv-tools,
  fetchpatch,
  perl,
  zlib,
  ccacheStdenv,
  tree,
  wrapCC,
  ctestCheckHook,
  rocmPackages ? {},
  cudaPackages ? {},
  levelZeroSupport ? true,
  openclSupport ? true,
  # Broken
  cudaSupport ? false,
  rocmSupport ? true,
  rocmGpuTargets ? builtins.concatStringsSep ";" rocmPackages.clr.gpuTargets,
  nativeCpuSupport ? false,
  vulkanSupport ? true,
  useLibcxx ? false,
  useLld ? true,
  buildTests ? true,
  buildDocs ? false,
  buildMan ? false,
}: let
  version = "unstable-2025-10-09";
  date = "20251009";
  llvmPackages = llvmPackages_21;
  # stdenv' =
  #   if useLibcxx
  #   then llvmPackages.libcxxStdenv
  #   else llvmPackages.stdenv;
  # stdenv = stdenv';
  # stdenv = ccacheStdenv.override {stdenv = stdenv';};
  stdenv = ccacheStdenv;
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
        cat > $out/bin/clang-22 <<EOF
        #!/bin/sh
        exec "${root}/bin/clang-22" "\$@"
        EOF
        chmod +x $out/bin/clang-22
        cp $out/bin/clang-22 $out/bin/clang
        cp $out/bin/clang-22 $out/bin/clang++
      '';
      passthru.isClang = true;
    }
  );
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "intel-llvm";
    inherit version;

    src = fetchFromGitHub {
      owner = "intel";
      repo = "llvm";
      # tag = "v${version}";
      rev = "a963e89b61345c8db16aa4cc2dd339d09ccf0638";
      hash = "sha256-OhGnQ4uKd6q8smB0ue+k+dVzQpBwapWvfrzOFFfBOic=";
    };

    outputs = [
      "out"
      "lib"
      "dev"
      "python"
    ];

    nativeBuildInputs =
      [
        cmake
        ninja
        python3
        pkg-config
        zlib
        zstd
      ]
      ++ lib.optionals useLld [
        llvmPackages.bintools
      ]
      ++ lib.optionals buildTests [
        perl
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
        parallel-hashmap
        #vc-intrinsics
      ]
      # ++ lib.optionals useLibcxx [
      #   llvmPackages.libcxx
      #   llvmPackages.libcxx.dev
      # ]
      ++ unified-runtime'.buildInputs;

    # separateDebugInfo = true;
    # dontFixup = true;

    propagatedBuildInputs = [
      zstd
      zlib
      libedit
    ];

    # # TODO: Is this needed?
    # nativeCheckInputs = lib.optionals buildTests [
    #   ctestCheckHook
    # ];
    checkTarget =
      if buildTests
      then "check-all"
      else null;

    cmakeBuildType = "Release";

    patches = [
      #(fetchpatch {
      #  name = "make-sycl-version-reproducible";
      #  url = "https://github.com/intel/llvm/commit/1c22570828e24a628c399aae09ce15ad82b924c6.patch";
      #  hash = "sha256-leBTUmanYaeoNbmA0m9VFX/5ViACuXidWUhohewshQQ=";
      #})
      ./gnu-install-dirs.patch
      #./gnu-install-dirs-2.patch
    ];

    postPatch =
      lib.optionalString buildTests ''
        # Fix scan-build scripts to use Nix perl instead of /usr/bin/env
        patchShebangs clang/tools/scan-build/libexec/
      ''
      + ''
          # Parts of libdevice are built using the freshly-built compiler.
          # As it tries to link to system libraries, we need to wrap it with the
          # usual nix cc-wrapper.
          # Since the compiler to be wrapped is not available at this point,
          # we use a stub that points to where it will be later on
          # in `/build/source/build/bin/clang-22`
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

        # `NO_CMAKE_PACKAGE_REGISTRY` prevents it from finding OpenCL, so we unset it
        # Note that this cmake file is imported in various places, not just unified-runtime
        substituteInPlace unified-runtime/cmake/FetchOpenCL.cmake \
            --replace-fail "NO_CMAKE_PACKAGE_REGISTRY" ""
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
          ${lib.optionalString useLld "--use-lld"} \
          ${lib.optionalString levelZeroSupport "--level_zero_adapter_version V1"} \
          ${lib.optionalString levelZeroSupport "--l0-headers ${lib.getInclude level-zero}/include/level_zero"} \
          ${lib.optionalString levelZeroSupport "--l0-loader ${lib.getLib level-zero}/lib/libze_loader.so"} \
          # --disable-jit # Currently broken afaict
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

      # cmakeFlagsArray+=(
      # "-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG -march=skylake -mtune=znver3 -flto=thin -ffat-lto-objects"
      # "-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG -march=skylake -mtune=znver3 -flto=thin -ffat-lto-objects"
      # )

      # patchShebangs llvm-spirv/tools/spirv-tool/gen_spirv.bash
      # type configurePhase
    '';

    cmakeDir = "/build/source/llvm";

    cmakeFlags =
      [
        # (lib.cmakeFeature "LLVM_TARGETS_TO_BUILD" (lib.concatStringsSep ";" llvmTargetsToBuild'))
        # (lib.cmakeFeature "LLVM_ENABLE_PROJECTS" (lib.concatStringsSep ";" llvmProjectsToBuild))
        #(lib.cmakeFeature "LLVM_HOST_TRIPLE" stdenv.hostPlatform.config)
        #(lib.cmakeFeature "LLVM_DEFAULT_TARGET_TRIPLE" stdenv.hostPlatform.config)
        (lib.cmakeBool "LLVM_INSTALL_UTILS" true)
        (lib.cmakeBool "LLVM_INCLUDE_DOCS" (buildDocs || buildMan))
        (lib.cmakeBool "MLIR_INCLUDE_DOCS" (buildDocs || buildMan))
        (lib.cmakeBool "LLVM_BUILD_DOCS" (buildDocs || buildMan))
        (lib.cmakeBool "LLVM_ENABLE_SPHINX" (buildDocs || buildMan))
        (lib.cmakeBool "SPHINX_OUTPUT_HTML" buildDocs)
        (lib.cmakeBool "SPHINX_OUTPUT_MAN" buildMan)
        (lib.cmakeBool "LLVM_BUILD_TESTS" buildTests)
        (lib.cmakeBool "LLVM_INCLUDE_TESTS" buildTests)
        (lib.cmakeBool "MLIR_INCLUDE_TESTS" buildTests)
        (lib.cmakeBool "SYCL_INCLUDE_TESTS" buildTests)

        #"-DLLVM_ENABLE_ZSTD=FORCE_ON"
        # TODO
        "-DLLVM_ENABLE_ZLIB=FORCE_ON"
        "-DLLVM_ENABLE_THREADS=ON"
        # Breaks tablegen build somehow
        # "-DLLVM_ENABLE_LTO=Thin"
        "-DLLVM_USE_STATIC_ZSTD=OFF"

        # Having these set to true breaks the build
        # See https://github.com/intel/llvm/issues/19060
        (lib.cmakeBool "BUILD_SHARED_LIBS" false)
        (lib.cmakeBool "LLVM_LINK_LLVM_DYLIB" false)
        (lib.cmakeBool "LLVM_BUILD_LLVM_DYLIB" false)

        # (lib.cmakeBool "LLVM_ENABLE_LIBCXX" useLibcxx)
        # (lib.cmakeFeature "CLANG_DEFAULT_CXX_STDLIB" (
        #   if useLibcxx
        #   then "libc++"
        #   else "libstdc++"
        # ))

        (lib.cmakeFeature "SYCL_COMPILER_VERSION" date)

        (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
        (lib.cmakeBool "FETCHCONTENT_QUIET" false)

        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_VC-INTRINSICS" "${deps.vc-intrinsics}")

        (lib.cmakeFeature "LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR" "${spirv-headers.src}")

        #"-DCMAKE_INSTALL_LIBDIR=${placeholder "out"}/lib"
        #"-DCMAKE_INSTALL_LIBEXECDIR=${placeholder "out"}/libexec"
        #"-DCMAKE_INSTALL_INCLUDEDIR=${placeholder "out"}/include"
        #"-DCMAKE_INSTALL_BINDIR=${placeholder "out"}/bin"

        # Override clang resource directory to use build-time path during build
        "-DCLANG_RESOURCE_DIR=lib/clang/22"

        # Direct CMake files to dev output (following nixpkgs pattern)
        (lib.cmakeFeature "LLVM_INSTALL_PACKAGE_DIR" "${placeholder "dev"}/lib/cmake/llvm")
      ]
      # ++ lib.optional useLld (lib.cmakeFeature "LLVM_USE_LINKER" "lld")
      ++ unified-runtime'.cmakeFlags;

    # This hardening option causes compilation errors when compiling for amdgcn, spirv and others
    # TODO: Can the cc wrapper be made aware of this somehow?
    hardeningDisable = ["zerocallusedregs"];

    # TODO: Investigate why this is needed
    NIX_LDFLAGS = "-lhwloc";

    requiredSystemFeatures = ["big-parallel"];
    enableParallelBuilding = true;

    postBuild = ''
      echo "=== Build directory structure (for debugging) ==="
      ${tree}/bin/tree -L 2 -d "$PWD" || find "$PWD" -maxdepth 2 -type d
      echo "=== Checking for scan-build files ==="
      ls -la "$PWD/libexec/" 2>/dev/null || echo "libexec directory does not exist"
      echo "=== Checking for math.h in clang resource directory ==="
      find "$PWD" -name "math.h" | head -5 || echo "No math.h found"
    '';

    doCheck = buildTests;

    preCheck = lib.optionalString buildTests ''
      # Set CLANG environment variable to use wrapped clang for tests
      # This is picked up by lit's use_llvm_tool("clang", search_env="CLANG", ...)
      # and ensures tests have access to stdlib headers
      export CLANG="${ccWrapperStub}/bin/clang++"
    '';

    # Copied from the regular LLVM derivation:
    #  pkgs/development/compilers/llvm/common/llvm/default.nix
    postInstall = ''
      mkdir -p $python/share
      mv $out/share/opt-viewer $python/share/opt-viewer

      # If this stays in $out/bin, it'll create a circular reference
      moveToOutput "bin/llvm-config*" "$dev"

      substituteInPlace "$dev/lib/cmake/llvm/LLVMExports-${lib.toLower finalAttrs.finalPackage.cmakeBuildType}.cmake" \
        --replace-fail "$out/bin/llvm-config" "$dev/bin/llvm-config"
      substituteInPlace "$dev/lib/cmake/llvm/LLVMConfig.cmake" \
        --replace-fail 'set(LLVM_BINARY_DIR "''${LLVM_INSTALL_PREFIX}")' 'set(LLVM_BINARY_DIR "'"$lib"'")'
    '';

    meta = with lib; {
      description = "Intel LLVM-based compiler with SYCL support";
      longDescription = ''
        Intel's LLVM-based compiler toolchain with Data Parallel C++ (DPC++)
        and SYCL support for heterogeneous computing across CPUs, GPUs, and FPGAs.
      '';
      homepage = "https://github.com/intel/llvm";
      license = with licenses; [ncsa asl20 llvm-exception];
      maintainers = with maintainers; [blenderfreaky];
      platforms = platforms.linux;
    };

    passthru = {
      isClang = true;
      # The llvm package set of the same version as
      # Intels compiler is based on
      baseLlvm = llvmPackages_21;
      inherit ccWrapperStub;
    };
  })
