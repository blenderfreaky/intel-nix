{
  lib,
  cmake,
  parallel-hashmap,
  ninja,
  llvmPackages_21,
  callPackage,
  fetchFromGitHub,
  runCommand,
  zlib,
  zstd,
  unified-runtime,
  hwloc,
  spirv-headers,
  spirv-tools,
  applyPatches,
  fetchpatch,
  libffi,
  libxml2,
  vc-intrinsics,
  emhash,
  libedit,
  tree,
  wrapCCWith,
  overrideCC,
  intel-compute-runtime,
  intel-graphics-compiler,
  opencl-headers,
  ocl-icd,
  spirv-llvm-translator,
  pkg-config,
  emptyDirectory,
  lit,
  # TODO: llvmPackages.libcxx? libcxxStdenv?
  libcxx,
  symlinkJoin,
  rocmPackages ? {},
  level-zero,
  levelZeroSupport ? true,
  openclSupport ? true,
  # Broken
  cudaSupport ? false,
  rocmSupport ? true,
  rocmGpuTargets ? builtins.concatStringsSep ";" rocmPackages.clr.gpuTargets,
  nativeCpuSupport ? false,
  vulkanSupport ? true,
  useLibcxx ? false,
  # This is a decent speedup over GNU ld
  useLld ? true,
  buildTests ? false,
  buildDocs ? false,
  buildMan ? false,
}: let
  version = "unstable-2025-09-04";
  date = "20250904";
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
  srcOrig = applyPatches {
    # src = fetchFromGitHub {
    #   owner = "intel";
    #   repo = "llvm";
    #   # tag = "v${version}";
    #   rev = "64928c5154d7a0d8b5f03e7771ce7411d14fea20";
    #   hash = "sha256-WTxZre8cpOQjR2K8TX3ygZxn5Math0ofs+l499RsgsI=";
    # };

    src = fetchFromGitHub {
      owner = "intel";
      repo = "llvm";
      # tag = "v${version}";
      rev = "0433e4d6f5c97f5870d4ffabcb3a7779ef9cf596";
      hash = "sha256-2wVVEpiWGd+/cCgv4qwY3h169BH6GOhNz+U2BQ3W11A=";
    };

    patches = [
      # https://github.com/intel/llvm/pull/19845
      (fetchpatch {
        name = "make-sycl-version-reproducible";
        url = "https://github.com/intel/llvm/commit/1c22570828e24a628c399aae09ce15ad82b924c6.patch";
        hash = "sha256-leBTUmanYaeoNbmA0m9VFX/5ViACuXidWUhohewshQQ=";
      })
    ];
  };
  src = runCommand "intel-llvm-src-fixed-${version}" {} ''
    cp -r ${srcOrig} $out
    chmod -R u+w $out

    # `NO_CMAKE_PACKAGE_REGISTRY` prevents it from finding OpenCL, so we unset it
    # Note that this cmake file is imported in various places, not just unified-runtime
    substituteInPlace $out/unified-runtime/cmake/FetchOpenCL.cmake \
      --replace-fail "NO_CMAKE_PACKAGE_REGISTRY" ""
  '';
  llvmPackages = llvmPackages_21;
  # TODO
  hostTarget =
    {
      "x86_64" = "X86";
      "aarch64" = "AArch64";
    }
    .${
      stdenv.targetPlatform.parsed.cpu.name
    }
      or (throw "Unsupported CPU architecture: ${stdenv.targetPlatform.parsed.cpu.name}");

  # TODO: Don't build targets not pulled in by *Support = true
  targetsToBuild' = "${hostTarget};SPIRV;AMDGPU;NVPTX";
  targetsToBuild = "host;SPIRV;AMDGPU;NVPTX";

  stdenv =
    if useLibcxx
    then llvmPackages.libcxxStdenv
    else llvmPackages.stdenv;
  llvmPkgs = llvmPackages.override (old: {
    inherit stdenv;
    #inherit src;

    version = "21.0.0-${srcOrig.rev}";

    # officialRelease = {};
    officialRelease = null;
    gitRelease = {
      rev = srcOrig.rev;
      rev-version = "21.0.0-unstable-2025-08-21";
    };

    monorepoSrc = src;

    doCheck = false;

    # enableSharedLibraries = false;

    # Not all projects need all these flags,
    # but I don't think it hurts to always include them.
    # libllvm needs all of them, so we're not losing
    # incremental builds or anything.
    devExtraCmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DLLVM_ENABLE_ZSTD=FORCE_ON"
      # TODO
      "-DLLVM_ENABLE_ZLIB=FORCE_ON"
      "-DLLVM_ENABLE_THREADS=ON"

      # Breaks tablegen build somehow
      # "-DLLVM_ENABLE_LTO=Thin"
      # "-DCMAKE_AR=${llvmPackages.bintools}/bin/ranlib"
      # "-DCMAKE_STRIP=${llvmPackages.bintools}/bin/ranlib"
      # "-DCMAKE_RANLIB=${llvmPackages.bintools}/bin/ranlib"

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

      (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_ONEAPI-CK" "${deps.oneapi-ck}")
    ];

    # TODO: This may break cross-compilation?
    buildLlvmTools =
      llvmPkgs
      // overrides
      // {
        libllvm = overrides.llvm;
        libclang = overrides.clang-unwrapped;
        libcxx = overrides.libcxx;
      };
    # // {
    #   tblgen = overrides.tblgen;
    # };
    libllvm = overrides.llvm;
    libclang = overrides.clang-unwrapped;
    libcxx = overrides.libcxx;
  });
  overrides = {
    tblgen = llvmPkgs.tblgen.overrideAttrs (old: {
      # TODO: This is sketchy
      # buildInputs = (old.buildInputs or []) ++ [vc-intrinsics];
      buildInputs =
        (old.buildInputs or [])
        ++ [
          zstd
          zlib
        ];
    });

    # Synthetic, not to be built directly
    llvm-base = llvmPkgs.llvm.overrideAttrs (
      old: let
        src' = runCommand "llvm-src-${version}" {inherit (src) passthru;} ''
          mkdir -p "$out"
          cp -r ${src}/llvm "$out"
          cp -r ${src}/cmake "$out"
          cp -r ${src}/third-party "$out"
          cp -r ${src}/libc "$out"

          cp -r ${src}/sycl "$out"
          cp -r ${src}/sycl-jit "$out"
          cp -r ${src}/llvm-spirv "$out"
          # cp -r ${src}/unified-runtime "$out"

          chmod u+w "$out/llvm/tools"
          cp -r ${src}/polly "$out/llvm/tools"

          # chmod u+w "$out/llvm/projects"
          # cp -r ${vc-intrinsics.src} "$out/llvm/projects"
        '';
      in {
        # inherit src;
        src = src';

        nativeBuildInputs =
          old.nativeBuildInputs
          ++ lib.optionals useLld [
            llvmPackages.bintools
          ];

        buildInputs =
          old.buildInputs
          ++ [
            stdenv.cc.cc.lib
            hwloc

            emhash

            zstd
            zlib
            libedit
            # spirv-llvm-translator'

            # vc-intrinsics

            # For libspirv_dis
            # spirv-tools

            # overrides.xpti
          ];
        # ++ unified-runtime'.buildInputs;

        propagatedBuildInputs = [
          zstd
          zlib
          libedit
          #   hwloc
        ];

        doCheck = false;

        cmakeFlags =
          old.cmakeFlags
          ++ [
            # Off to save build time, TODO: Reenable
            # "-DLLVM_ENABLE_LTO=Thin"

            # TODO: Only enable conditionally
            # Maybe conditional will cause issues with libclc (looking at buildbot/configure.py)
            # ??

            # # This cuts build time a bit but I'm unsure if this should be kept
            # "-DLLVM_TARGETS_TO_BUILD=${targetsToBuild}"

            # "-DLLVM_EXTERNAL_VC_INTRINSICS_SOURCE_DIR=${vc-intrinsics.src}"
            #"-DLLVM_EXTERNAL_PROJECTS=sycl;llvm-spirv;opencl;xpti;xptifw;libdevice;sycl-jit"
            # "-DLLVM_EXTERNAL_PROJECTS=sycl;llvm-spirv"
            # "-DLLVM_EXTERNAL_PROJECTS=llvm-spirv"
            # "-DLLVM_EXTERNAL_SYCL_SOURCE_DIR=/build/${src'.name}/sycl"
            # "-DLLVM_EXTERNAL_LLVM_SPIRV_SOURCE_DIR=/build/${src'.name}/llvm-spirv"
            #"-DLLVM_EXTERNAL_XPTI_SOURCE_DIR=/build/${src'.name}/xpti"
            #"-DXPTI_SOURCE_DIR=/build/${src'.name}/xpti"
            #"-DLLVM_EXTERNAL_XPTIFW_SOURCE_DIR=/build/${src'.name}/xptifw"
            #"-DLLVM_EXTERNAL_LIBDEVICE_SOURCE_DIR=/build/${src'.name}/libdevice"
            # "-DLLVM_EXTERNAL_SYCL_JIT_SOURCE_DIR=/build/${src'.name}/sycl-jit"
            #"-DLLVM_ENABLE_PROJECTS=clang\;sycl\;llvm-spirv\;opencl\;xpti\;xptifw\;libdevice\;sycl-jit\;libclc\;lld"
            # "-DLLVM_ENABLE_PROJECTS=llvm-spirv"

            # These require clang, which we don't have at this point.
            # TODO: Build these later, e.g. in passthru.tests
            # "-DLLVM_SPIRV_INCLUDE_TESTS=OFF"

            # "-DLLVM_SPIRV_ENABLE_LIBSPIRV_DIS=ON"

            "-DLLVM_BUILD_TOOLS=ON"

            # "-DSYCL_ENABLE_XPTI_TRACING=ON"
            # "-DSYCL_ENABLE_BACKENDS=level_zero;level_zero_v2;cuda;hip"

            # "-DSYCL_INCLUDE_TESTS=ON"

            # "-DSYCL_ENABLE_WERROR=ON"

            # # # Currently broken. IDK if this is even useful though.
            # # "-DLLVM_USE_STATIC_ZSTD=ON"

            # "-DSYCL_ENABLE_EXTENSION_JIT=ON"
            # "-DSYCL_ENABLE_MAJOR_RELEASE_PREVIEW_LIB=ON"
            # "-DSYCL_ENABLE_WERROR=ON"
            # "-DSYCL_BUILD_PI_HIP_PLATFORM=AMD"

            # (if pkgs.stdenv.cc.isClang then throw "hiii" else "")
          ]
          # ++ lib.optionals pkgs.stdenv.cc.isClang [
          #   # (lib.cmakeFeature "CMAKE_C_FLAGS_RELEASE" "-flto=thin\\\\ -ffat-lto-objects")
          #   # (lib.cmakeFeature "CMAKE_CXX_FLAGS_RELEASE" "-flto=thin\\\\ -ffat-lto-objects")
          #   "-DCMAKE_C_FLAGS_RELEASE=-flto=thin -ffat-lto-objects"
          #   "-DCMAKE_CXX_FLAGS_RELEASE=-flto=thin -ffat-lto-objects"
          # ]
          ++ lib.optional useLld (lib.cmakeFeature "LLVM_USE_LINKER" "lld")
          # ++ unified-runtime'.cmakeFlags
          # ++ ["-DUR_ENABLE_TRACING=OFF"]
          ;

        preConfigure =
          old.preConfigure
          + ''
            cmakeFlagsArray+=(
              "-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG -march=skylake -mtune=znver3 -flto=thin -ffat-lto-objects"
              "-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG -march=skylake -mtune=znver3 -flto=thin -ffat-lto-objects"
            )
          '';

        postInstall =
          ''
            # Check if the rogue include directory was created in $out
            if [ -d $out/include ]; then
              # Move its contents to the correct destination

              echo "searchmarker 123123123"
              echo ------------
              ${tree}/bin/tree $out
              echo ------------
              ${tree}/bin/tree $dev
              echo ------------

              mv $out/include/LLVMSPIRVLib $dev/include/
              mv $out/include/llvm/ExecutionEngine/Interpreter/* $dev/include/llvm/ExecutionEngine/Interpreter/
              mv $out/include/llvm/SYCLLowerIR/* $dev/include/llvm/SYCLLowerIR/

              # Remove the now-empty directory so fixupPhase doesn't see it
              rmdir $out/include/llvm/ExecutionEngine/Interpreter
              rmdir $out/include/llvm/ExecutionEngine
              rmdir $out/include/llvm/SYCLLowerIR
              rmdir $out/include/llvm
              rmdir $out/include
            fi
          ''
          + (old.postInstall or "");
        #
        postFixup =
          (old.postFixup or "")
          + ''
            #####################################
            # Patch *.cmake and *.pc files
            #####################################
            find "$dev" -type f \( -name "*.cmake" -o -name "*.pc" \) | while read -r f; do
              tmpf="$(mktemp)"
              cp "$f" "$tmpf"

              sed -i \
                -e 's|'"$out"'/include|'"$dev"'/include|g' \
                -e 's|''${_IMPORT_PREFIX}/include|'$dev'/include|g' \
                "$f"

              if ! diff -q "$tmpf" "$f" >/dev/null; then
                echo "Changed: $f"
                diff -u "$tmpf" "$f" || true
              fi

              rm -f "$tmpf"
            done || true

            #####################################
            # Patch executables in bin directory
            #####################################
            if [ -d "$dev/bin" ]; then
              find "$dev/bin" -type f -executable | while read -r f; do
                tmpf="$(mktemp)"
                cp "$f" "$tmpf"

                sed -i \
                  -e 's|'"$out"'/include|'"$dev"'/include|g' \
                  "$f" 2>/dev/null || true

                if ! diff -q "$tmpf" "$f" >/dev/null; then
                  echo "Changed: $f"
                  diff -u "$tmpf" "$f" || true
                fi

                rm -f "$tmpf"
              done || true
            fi          '';
      }
    );

    llvm-no-spirv = overrides.llvm-base.overrideAttrs (oldAttrs: {
      postPatch =
        oldAttrs.postPatch
        + ''
          rm -rf tools/spirv-to-ir-wrapper
        '';
    });

    llvm-with-intree-spirv = overrides.llvm-base.overrideAttrs (oldAttrs: {
      cmakeFlags =
        oldAttrs.cmakeFlags
        ++ [
          "-DLLVM_EXTERNAL_PROJECTS=llvm-spirv"
          "-DLLVM_EXTERNAL_LLVM_SPIRV_SOURCE_DIR=/build/${oldAttrs.src.name}/llvm-spirv"

          # These require clang, which we don't have at this point.
          # TODO: Build these later, e.g. in passthru.tests
          "-DLLVM_SPIRV_INCLUDE_TESTS=OFF"

          "-DLLVM_SPIRV_ENABLE_LIBSPIRV_DIS=ON"
        ];

      buildInputs =
        oldAttrs.buildInputs
        ++ [
          # For libspirv_dis
          spirv-tools
        ];
    });

    spirv-to-ir-wrapper = stdenv.mkDerivation (finalAttrs: {
      pname = "spirv-to-ir-wrapper";
      inherit version;

      src = runCommand "spirv-to-ir-wrapper-src-${version}" {inherit (src) passthru;} ''
        mkdir -p "$out"
        cp -r ${src}/llvm/tools/spirv-to-ir-wrapper "$out"
      '';

      sourceRoot = "${finalAttrs.src.name}/spirv-to-ir-wrapper";

      patches = [./patches/spirv-to-ir-wrapper.patch];

      nativeBuildInputs = [cmake ninja overrides.llvm-no-spirv.dev overrides.spriv-llvm-translator.dev];
      buildInputs = [overrides.llvm-no-spirv overrides.spriv-llvm-translator];
    });

    # llvm = symlinkJoin {
    #   name = "llvm";
    #   paths = [overrides.spirv-to-ir-wrapper overrides.llvm-no-spirv];
    # };
    # llvm = overrides.llvm-no-spirv;
    # llvm = overrides.llvm-base;
    llvm = overrides.llvm-with-intree-spirv;

    opencl-aot = stdenv.mkDerivation (finalAttrs: {
      pname = "opencl-aot";
      inherit version;
      src = runCommand "opencl-aot-src-${version}" {inherit (src) passthru;} ''
        mkdir -p "$out"
        cp -r ${src}/opencl "$out"
        # cp -r ${src}/cmake "$out"

        # mkdir -p "$out/cmake"
        mkdir -p "$out/unified-runtime/cmake"
        cp -r ${src}/unified-runtime/cmake/FetchOpenCL.cmake "$out/unified-runtime/cmake"
      '';
      # inherit src;
      #
      patches = [
        ./patches/opencl.patch
        # ./patches/opencl-aot.patch
      ];

      sourceRoot = "${finalAttrs.src.name}/opencl";
      # sourceRoot = "${finalAttrs.src.name}/sycl";

      # outputs = [
      #   "out"
      #   "dev"
      #   "lib"
      # ];

      nativeBuildInputs = [cmake ninja];
      buildInputs = [overrides.llvm libffi zstd zlib libxml2 opencl-headers ocl-icd];

      # nativeBuildInputs = [cmake ninja] ++ unified-runtime'.nativeBuildInputs;

      # buildInputs = [overrides.xpti] ++ unified-runtime'.buildInputs;

      cmakeFlags = [
        # "-DLLVM_TARGETS_TO_BUILD=${targetsToBuild'}"
        # "-DCMAKE_MODULE_PATH=${finalAttrs.src}/cmake"
        "-DLLVM_BUILD_TOOLS=ON"
        # (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-HEADERS" "${deps.opencl-headers}")
        # (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-ICD" "${deps.opencl-icd-loader}")
      ];
    });

    libclc =
      (llvmPkgs.libclc.override {
        llvm = overrides.llvm;
      }).overrideAttrs (old: {
        nativeBuildInputs = builtins.filter (x: lib.getName x != "SPIRV-LLVM-Translator") old.nativeBuildInputs;

        buildInputs =
          old.buildInputs
          ++ [
            zstd
            zlib
            # Required by libclc-remangler
            llvmPkgs.clang.cc.dev
          ];

        cmakeFlags = [
          # Otherwise it'll misdetect the unwrapped just-built compiler as the compiler to use,
          # and configure will fail to compile a basic test program with it.
          (lib.cmakeFeature "CMAKE_C_COMPILER" "${stdenv.cc}/bin/clang")
          (lib.cmakeFeature "LLVM_EXTERNAL_LIT" "${lit}/bin/lit")

          "-DLLVM_BUILD_UTILS=ON"
          "-DLLVM_INSTALL_UTILS=ON"

          # (lib.cmakeBool "LIBCLC_GENERATE_REMANGLED_VARIANTS" false)
        ];

        patches =
          [(builtins.head old.patches)]
          ++ [
            ./patches/libclc-use-default-paths.patch
            ./patches/libclc-remangler.patch
            ./patches/libclc-find-clang.patch
            ./patches/libclc-utils.patch
          ];

        preInstall = ''
          # TODO: Figure out why this is needed
          cp utils/prepare_builtins prepare_builtins
        '';
      });

    vc-intrinsics = vc-intrinsics.override {
      # llvmPackages_21 = llvmPkgs // overrides;
    };

    # spirv-llvm-translator = stdenv.mkDerivation (finalAttrs: {
    spirv-llvm-translator = (spirv-llvm-translator.override {llvm = overrides.llvm;}).overrideAttrs (oldAttrs: let
      src' = runCommand "sycl-src-${version}" {inherit (src) passthru;} ''
        mkdir -p "$out"
        cp -r ${src}/llvm-spirv "$out"
      '';
    in {
      # pname = "SPIRV-LLVM-Translator";
      # inherit version;
      src = src';
      sourceRoot = "${src'.name}/llvm-spirv";

      # nativeBuildInputs = [
      #   pkg-config
      #   cmake
      #   llvmPackages.llvm.dev
      # ];
    });

    sycl = stdenv.mkDerivation (finalAttrs: {
      pname = "sycl";
      inherit version;
      # src = runCommand "sycl-src-${version}" {inherit (src) passthru;} ''
      #   mkdir -p "$out"
      #   cp -r ${src}/sycl "$out"
      #   cp -r ${src}/cmake "$out"

      #   chmod u+w "$out/sycl"
      #   cp -r ${src}/unified-runtime "$out/sycl"

      #   mkdir -p "$out/sycl/llvm/cmake"
      #   cp -r ${src}/llvm/cmake/modules "$out/sycl/llvm/cmake/modules"
      # '';
      inherit src;

      patches = [
        ./patches/sycl.patch
        ./patches/sycl-build-ur.patch
        # ./patches/sycl-incl.patch
        # ./patches/unified-runtime.patch
        # ./patches/unified-runtime-2.patch
      ];
      # prePatch = ''
      #   ls ../unified-runtime
      #   cat ../unified-runtime/source/adapters/level_zero/common.cpp
      # '';
      postPatch = ''
        pushd ../unified-runtime
        chmod -R u+w .
        patch -p1 < ${./patches/unified-runtime.patch}
        patch -p1 < ${./patches/unified-runtime-2.patch}
        popd
      '';

      # sourceRoot = "${finalAttrs.src.name}/llvm";
      sourceRoot = "${finalAttrs.src.name}/sycl";

      nativeBuildInputs = [cmake ninja pkg-config] ++ unified-runtime'.nativeBuildInputs;

      buildInputs =
        [
          overrides.xpti
          overrides.xptifw
          # Might need to be propagated
          overrides.opencl-aot
          overrides.llvm
          llvmPkgs.clang
          llvmPkgs.clang.cc.dev
          # overrides.vc-intrinsics
          (zstd.override {enableStatic = true;})
          zlib

          emhash
        ]
        ++ (lib.optional (rocmSupport || cudaSupport) overrides.libclc)
        ++ (lib.optional rocmSupport llvmPkgs.lld)
        ++ unified-runtime'.buildInputs;

      # preBuild = ''
      #   ${tree}/bin/tree
      #   echo ----
      #   ${tree}/bin/tree tools
      # '';
      #
      # preConfigure = ''
      #   chmod u+w .
      #   mkdir -p build/include-build-dir
      # '';

      cmakeFlags =
        [
          # Used to find unified-runtime folder (`LLVM_SOURCE_DIR/../unified-runtime`)
          "-DLLVM_SOURCE_DIR=/build/${finalAttrs.src.name}/llvm"
          # "-DUR_INTREE_SOURCE_DIR=/build/${finalAttrs.src.name}/unified-runtime"
          # "-DSYCL_INCLUDE_BUILD_DIR=/build/${finalAttrs.src.name}/build/include-build-dir"

          (lib.cmakeFeature "LLVM_EXTERNAL_LIT" "${lit}/bin/lit")

          # "-DLLVM_ENABLE_PROJECTS=sycl;opencl;xpti;xptifw;sycl-jit;libclc"
          # "-DLLVM_ENABLE_PROJECTS=sycl;sycl-jit"

          # "-DLLVM_EXTERNAL_PROJECTS=sycl;xpti;xptifw;sycl-jit"
          "-DLLVM_EXTERNAL_XPTI_SOURCE_DIR=/build/${finalAttrs.src.name}/xpti"
          "-DLLVM_EXTERNAL_XPTIFW_SOURCE_DIR=/build/${finalAttrs.src.name}/xptifw"
          "-DLLVM_EXTERNAL_SYCL_JIT_SOURCE_DIR=/build/${finalAttrs.src.name}/sycl-jit"

          # "-DLLVM_USE_STATIC_ZSTD=OFF"

          # TODO: Reenable!
          "-DSYCL_ENABLE_XPTI_TRACING=OFF"
          # "-DSYCL_ENABLE_BACKENDS=level_zero;level_zero_v2;cuda;hip"
          "-DSYCL_ENABLE_BACKENDS=${lib.strings.concatStringsSep ";" unified-runtime'.backends}"

          "-DLLVM_INCLUDE_TESTS=ON"
          "-DSYCL_INCLUDE_TESTS=ON"

          # "-DSYCL_ENABLE_WERROR=ON"

          # TODO: REENABLE!
          "-DSYCL_ENABLE_EXTENSION_JIT=OFF"
          # "-DSYCL_ENABLE_EXTENSION_JIT=ON"
          "-DSYCL_ENABLE_MAJOR_RELEASE_PREVIEW_LIB=ON"
          "-DSYCL_BUILD_PI_HIP_PLATFORM=AMD"

          (lib.cmakeFeature "SYCL_COMPILER_VERSION" date)

          (lib.cmakeBool "SYCL_UR_USE_FETCH_CONTENT" false)

          # # Lookup broken
          # (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_EMHASH" "${deps.emhash}")
        ]
        ++ unified-runtime'.cmakeFlags;
    });

    libdevice = stdenv.mkDerivation (finalAttrs: let
      tools = symlinkJoin {
        name = "libdevice-tools";
        paths = [
          overrides.llvm
          llvmPkgs.clang
          llvmPkgs.clang-tools
        ];
        # # I think it wants unwrapped clang and wrapped clang++
        # # but I'm not sure yet. TODO
        postBuild =
          ''
            rm $out/bin/clang
            # ln -s ${overrides.clang-unwrapped}/bin/clang $out/bin/clang
            ln -s $out/bin/clang++ $out/bin/clang
          ''
          + (lib.optionalString (rocmSupport || cudaSupport) ''
            ln -s ${overrides.libclc}/bin/prepare_builtins $out/bin/prepare_builtins
          '');
      };
    in {
      pname = "libdevice";
      inherit version;

      inherit src;
      sourceRoot = "${finalAttrs.src.name}/libdevice";

      nativeBuildInputs = [cmake ninja];

      buildInputs = [
        overrides.llvm
        # llvmPkgs.clang
        # llvmPkgs.clang-tools
        overrides.sycl
        tools
      ];

      patches = [
        ./patches/libdevice.patch
        ./patches/libdevice-sycllibdevice.patch
      ];

      hardeningDisable = ["zerocallusedregs"];

      NIX_CFLAGS_COMPILE = "-v";

      ninjaFlags = ["-v"];

      cmakeFlags = [
        "-DLLVM_TOOLS_DIR=${overrides.llvm}/bin"
        "-DCLANG_TOOLS_DIR=${llvmPkgs.clang-tools}/bin"
        # (lib.cmakeFeature "CMAKE_C_COMPILER" "${stdenv.cc}/bin/clang")
        # Despite being in libdevice, this flag is called LIBCLC_
        "-DLIBCLC_CUSTOM_LLVM_TOOLS_BINARY_DIR=${tools}/bin"
        "-DLLVM_TARGETS_TO_BUILD=${targetsToBuild}"
      ];
    });

    sycl-jit = stdenv.mkDerivation (finalAttrs: {
      pname = "sycl-jit";
      inherit version;

      inherit src;

      sourceRoot = "${finalAttrs.src.name}/sycl-jit";

      nativeBuildInputs = [cmake ninja];

      # buildInputs = [ llvm ];

      # cmakeFlags = [
      #   "-DSYCL_ENABLE_WERROR=ON"
      #   "-DSYCL_ENABLE_EXTENSION_JIT=ON"
      #   "-DSYCL_ENABLE_MAJOR_RELEASE_PREVIEW_LIB=ON"
      #   "-DSYCL_ENABLE_WERROR=ON"
      #   "-DSYCL_BUILD_PI_HIP_PLATFORM=AMD"
      # ];
    });

    clang-unwrapped = (llvmPkgs.clang-unwrapped.override {}).overrideAttrs (old: {
      buildInputs =
        (old.buildInputs or [])
        ++ [
          zstd
          zlib
          libedit
          # overrides.llvm.dev
        ];

      prePatch = ''
        echo hiiii
      '';
      patchPhase = ''
        echo hiii
        exit 1
      '';
      postPatch = ''
        ${old.postPatch or ""}

        echo AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA

        exit 1

        substituteInPlace lib/Driver/CMakeLists.txt \
            --replace-fail "DeviceConfigFile" ""
            echo BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB

        # The findProgram calls in this file are often split across multiple lines.
        # Use sed to join them into a single line so that substituteInPlace can match them.
        # This handles cases where the line break is after '=' or after '('.
        sed -i \
            -e '/Expected<std::string>.*=$/{N;s/\n\s*//}' \
            -e '/findProgram($/{N;s/\n\s*//}' \
            tools/clang-linker-wrapper/ClangLinkerWrapper.cpp

        # We want to use a shell-expansion here, as the name contains a version number (e.g., ocloc-25.31.1).
        OCLOC="${intel-compute-runtime}/bin/ocloc-*"
        # TODO: clang-offload-bundler will not be wrapper properly

        substituteInPlace tools/clang-linker-wrapper/ClangLinkerWrapper.cpp \
            --replace-fail 'findProgram("llvm-objcopy", {getMainExecutable("llvm-objcopy")})' '"${overrides.llvm}/bin/llvm-objcopy"' \
            --replace-fail 'findProgram("clang-offload-bundler", {getMainExecutable("clang-offload-bundler")})' '"$out/bin/clang-offload-bundler"' \
            --replace-fail 'findProgram("spirv-to-ir-wrapper", {getMainExecutable("spirv-to-ir-wrapper")})' '"${overrides.llvm}/bin/spirv-to-ir-wrapper"' \
            --replace-fail 'findProgram("sycl-post-link", {getMainExecutable("sycl-post-link")})' '"${overrides.llvm}/bin/sycl-post-link"' \
            --replace-fail 'findProgram("llvm-spirv", {getMainExecutable("llvm-spirv")})' '"${overrides.llvm}/bin/llvm-spirv"' \
            --replace-fail 'findProgram("opencl-aot", {getMainExecutable("opencl-aot")})' '"${overrides.opencl-aot}/bin/opencl-aot"' \
            --replace-fail 'findProgram("ocloc", {getMainExecutable("ocloc")})' '"$OCLOC"' \
            --replace-fail 'findProgram("clang", {getMainExecutable("clang")})' '"${llvmPkgs.clang}/bin/clang"' \
            --replace-fail 'findProgram("llvm-link", {getMainExecutable("llvm-link")})' '"${overrides.llvm}/bin/llvm-link"'

        # Apply the same pattern to the second file, which has a slightly different
        # function signature for findProgram.
        sed -i \
            -e '/Expected<std::string>.*=$/{N;s/\n\s*//}' \
            tools/clang-sycl-linker/ClangSYCLLinker.cpp

        substituteInPlace tools/clang-sycl-linker/ClangSYCLLinker.cpp \
            --replace-fail 'findProgram(Args, "opencl-aot", {getMainExecutable("opencl-aot")})' '"${overrides.opencl-aot}/bin/opencl-aot"' \
            --replace-fail 'findProgram(Args, "ocloc", {getMainExecutable("ocloc")})' '"$OCLOC"'

        # # After replacing the calls that use it, the getMainExecutable function
        # # in this file is no longer needed. Remove it to prevent compiler warnings
        # # or errors about unused functions.
        # sed -i '/^std::string getMainExecutable(const char \*Name) {/,/}/d' \
        #   clang/tools/clang-sycl-linker/ClangSYCLLinker.cpp
      '';

      # cmakeFlags =
      #   (old.cmakeFlags or [])
      #   ++ [
      #     (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
      #     (lib.cmakeBool "FETCHCONTENT_QUIET" false)

      #     (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_VC-INTRINSICS" "${deps.vc-intrinsics}")
      #   ];
    });

    # clang-tools = llvmPkgs.clang-tools.overrideAttrs (old: {

    # });

    libcxx = llvmPkgs.libcxx.overrideAttrs (old: {
      # inherit stdenv;
      buildInputs = old.buildInputs ++ [zstd zlib];
    });

    # # # pick clang appropriate for package set we are targeting
    # # clang =
    # #   # if stdenv.targetPlatform.libc == null
    # #   # then tools.clangNoLibc
    # #   # else if stdenv.targetPlatform.useLLVM or false
    # #   # then tools.clangUseLLVM
    # #   # else
    # #   if (stdenv).cc.isGNU
    # #   then overrides.libstdcxxClang
    # #   else overrides.libcxxClang;
    # bintools = llvmPkgs.bintools;

    # mkExtraBuildCommands0 = cc:
    #   ''
    #     rsrc="$out/resource-root"
    #     mkdir "$rsrc"
    #     echo "-resource-dir=$rsrc" >> $out/nix-support/cc-cflags
    #   ''
    #   # clang standard c headers are incompatible with FreeBSD so we have to put them in -idirafter instead of -resource-dir
    #   # see https://github.com/freebsd/freebsd-src/commit/f382bac49b1378da3c2dd66bf721beaa16b5d471
    #   + (
    #     if stdenv.targetPlatform.isFreeBSD
    #     then ''
    #       echo "-idirafter ${lib.getLib cc}/lib/clang/${lib.versions.major overrides.llvm.version}/include" >> $out/nix-support/cc-cflags
    #     ''
    #     else ''
    #       ln -s "${lib.getLib cc}/lib/clang/${lib.versions.major overrides.llvm.version}/include" "$rsrc"
    #     ''
    #   );

    # mkExtraBuildCommands = cc:
    #   overrides.mkExtraBuildCommands0 cc
    #   + ''
    #     ln -s "${llvmPkgs.compiler-rt.out}/lib" "$rsrc/lib"
    #     ln -s "${llvmPkgs.compiler-rt.out}/share" "$rsrc/share"
    #   '';

    # clangNoLibcNoRt = wrapCCWith rec {
    #   cc = overrides.clang-unwrapped;
    #   libcxx = null;
    #   bintools = llvmPkgs.bintoolsNoLibc;
    #   extraPackages = [];
    #   # "-nostartfiles" used to be needed for pkgsLLVM, causes problems so don't include it.
    #   extraBuildCommands = overrides.mkExtraBuildCommands0 cc;

    #   # "-nostartfiles" used to be needed for pkgsLLVM, causes problems so don't include it.
    #   nixSupport.cc-cflags = lib.optional (
    #     stdenv.targetPlatform.isWasm
    #   ) "-fno-exceptions";
    # };

    # clang = overrideCC

    # libstdcxxClang = wrapCCWith rec {
    #   cc = overrides.clang-unwrapped;
    #   # libstdcxx is taken from gcc in an ad-hoc way in cc-wrapper.
    #   libcxx = null;
    #   extraPackages = [llvmPkgs.compiler-rt];
    #   extraBuildCommands = overrides.mkExtraBuildCommands cc;
    # };

    # libcxxClang = wrapCCWith rec {
    #   cc = overrides.clang-unwrapped;
    #   libcxx = libcxx.libcxx;
    #   extraPackages = [llvmPkgs.compiler-rt];
    #   extraBuildCommands = overrides.mkExtraBuildCommands cc;
    # };

    # clangWithLibcAndBasicRt = wrapCCWith (
    #         rec {
    #           cc = overrides.clang-unwrapped;
    #           libcxx = null;
    #           bintools = bintools';
    #           extraPackages = [ targetLlvmLibraries.compiler-rt-no-libc ];
    #           extraBuildCommands =
    #             lib.optionalString (lib.versions.major metadata.release_version == "13") ''
    #               echo "-rtlib=compiler-rt" >> $out/nix-support/cc-cflags
    #               echo "-B${targetLlvmLibraries.compiler-rt-no-libc}/lib" >> $out/nix-support/cc-cflags
    #               echo "-nostdlib++" >> $out/nix-support/cc-cflags
    #             ''
    #             + mkExtraBuildCommandsBasicRt cc;
    #         }
    #         // lib.optionalAttrs (lib.versionAtLeast metadata.release_version "14") {
    #           nixSupport.cc-cflags = [
    #             "-rtlib=compiler-rt"
    #             "-B${targetLlvmLibraries.compiler-rt-no-libc}/lib"
    #             "-nostdlib++"
    #           ]
    #           ++ lib.optional (
    #             lib.versionAtLeast metadata.release_version "15" && stdenv.targetPlatform.isWasm
    #           ) "-fno-exceptions";
    #         }
    #       );
    # # stdenv = overrideCC stdenv llvmPkgs.clang;

    # libcxxStdenv = overrideCC stdenv llvmPkgs.libcxxClang;
    stdenv = overrideCC stdenv llvmPkgs.libcxxClang;

    xpti = stdenv.mkDerivation (finalAttrs: {
      pname = "xpti";
      inherit version;

      src = runCommand "xpti-src-${version}" {inherit (src) passthru;} ''
        mkdir -p "$out"
        cp -r ${src}/xpti "$out"
      '';

      sourceRoot = "${finalAttrs.src.name}/xpti";

      nativeBuildInputs = [
        cmake
        ninja
      ];

      cmakeFlags = [
        (lib.cmakeBool "XPTI_ENABLE_WERROR" true)
      ];
    });

    xptifw = stdenv.mkDerivation (finalAttrs: {
      pname = "xptifw";
      inherit version;

      src = runCommand "xptifw-src-${version}" {inherit (src) passthru;} ''
        mkdir -p "$out"
        cp -r ${src}/xptifw "$out"

        mkdir -p "$out/sycl/cmake/modules"
        cp ${src}/sycl/cmake/modules/FetchEmhash.cmake "$out/sycl/cmake/modules"
      '';

      sourceRoot = "${finalAttrs.src.name}/xptifw";

      nativeBuildInputs = [
        cmake
        ninja
      ];

      buildInputs = [
        parallel-hashmap
        emhash
        overrides.xpti
      ];

      # TODO
      cmakeFlags = [
        # # Lookup broken
        # (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_EMHASH" "${deps.emhash}")
        # # Lookup not implemented
        # (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_PARALLEL-HASHMAP" "${parallel-hashmap.src}")

        (lib.cmakeBool "XPTI_ENABLE_WERROR" true)
      ];
    });
  };
in
  llvmPkgs // overrides
