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
  libffi,
  libxml2,
  vc-intrinsics,
  emhash,
  libedit,
  tree,
  wrapCCWith,
  overrideCC,
  intel-compute-runtime,
  emptyDirectory,
  # TODO: llvmPackages.libcxx? libcxxStdenv?
  libcxx,
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
  version = "6.2.0";
  date = "20250815";
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
  srcOrig = fetchFromGitHub {
    owner = "intel";
    repo = "llvm";
    tag = "v${version}";
    # rev = "1dee8fc72d540109e13ea80193caa4432545790a";
    hash = "sha256-j8+DmGKO0qDF5JjH+DlkLKs1kBz6dS7ukwySd/Crqv0=";
  };
  src = runCommand "intel-llvm-src-fixed-${version}" {} ''
    cp -r ${srcOrig} $out
    chmod -R u+w $out

    # The latter is used everywhere except this one file. For some reason,
    # the former is not set, at least when building with Nix, so we replace it.
    # See also: github.com/intel/llvm/pull/19637
    substituteInPlace $out/unified-runtime/cmake/helpers.cmake \
      --replace-fail "PYTHON_EXECUTABLE" "Python3_EXECUTABLE"

    # Some libraries check for the version of the compiler.
    # For some reason, this version is determined by the
    # date of compilation. As the nix sandbox tells CMake
    # it's running at Unix epoch, this will always result in
    # a waaaay too old version.
    # To avoid this, we set the version to a fixed value.
    # See also: https://github.com/intel/llvm/issues/19692
    substituteInPlace $out/sycl/CMakeLists.txt \
      --replace-fail 'string(TIMESTAMP __SYCL_COMPILER_VERSION "%Y%m%d")' 'set(__SYCL_COMPILER_VERSION "${date}")'
  '';
  llvmPackages = llvmPackages_21;
  # TODO: I'm not sure whether we need to override the src, or if
  # they just vendored upstream without patches.

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

    officialRelease = {};

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

      (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
      (lib.cmakeBool "FETCHCONTENT_QUIET" false)

      (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_VC-INTRINSICS" "${deps.vc-intrinsics}")

      (lib.cmakeFeature "LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR" "${spirv-headers.src}")

      # These can be switched over to nixpkgs versions once they're updated
      # See: https://github.com/NixOS/nixpkgs/pull/428558
      (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-HEADERS" "${deps.opencl-headers}")
      (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-ICD" "${deps.opencl-icd-loader}")

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

    llvm-unpatched = llvmPkgs.llvm.overrideAttrs (
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
            llvmPackages_21.bintools
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
            spirv-tools

            overrides.xpti
          ]
          ++ unified-runtime'.buildInputs;

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
            "-DLLVM_TARGETS_TO_BUILD=${targetsToBuild}"

            # "-DLLVM_EXTERNAL_VC_INTRINSICS_SOURCE_DIR=${vc-intrinsics.src}"
            #"-DLLVM_EXTERNAL_PROJECTS=sycl;llvm-spirv;opencl;xpti;xptifw;libdevice;sycl-jit"
            # "-DLLVM_EXTERNAL_PROJECTS=sycl;llvm-spirv"
            "-DLLVM_EXTERNAL_PROJECTS=llvm-spirv"
            # "-DLLVM_EXTERNAL_SYCL_SOURCE_DIR=/build/${src'.name}/sycl"
            "-DLLVM_EXTERNAL_LLVM_SPIRV_SOURCE_DIR=/build/${src'.name}/llvm-spirv"
            #"-DLLVM_EXTERNAL_XPTI_SOURCE_DIR=/build/${src'.name}/xpti"
            #"-DXPTI_SOURCE_DIR=/build/${src'.name}/xpti"
            #"-DLLVM_EXTERNAL_XPTIFW_SOURCE_DIR=/build/${src'.name}/xptifw"
            #"-DLLVM_EXTERNAL_LIBDEVICE_SOURCE_DIR=/build/${src'.name}/libdevice"
            # "-DLLVM_EXTERNAL_SYCL_JIT_SOURCE_DIR=/build/${src'.name}/sycl-jit"
            #"-DLLVM_ENABLE_PROJECTS=clang\;sycl\;llvm-spirv\;opencl\;xpti\;xptifw\;libdevice\;sycl-jit\;libclc\;lld"
            # "-DLLVM_ENABLE_PROJECTS=llvm-spirv"

            # These require clang, which we don't have at this point.
            # TODO: Build these later, e.g. in passthru.tests
            "-DLLVM_SPIRV_INCLUDE_TESTS=OFF"

            "-DLLVM_SPIRV_ENABLE_LIBSPIRV_DIS=ON"

            "-DLLVM_BUILD_TOOLS=ON"

            "-DSYCL_ENABLE_XPTI_TRACING=ON"
            "-DSYCL_ENABLE_BACKENDS=level_zero;level_zero_v2;cuda;hip"

            "-DSYCL_INCLUDE_TESTS=ON"

            "-DSYCL_ENABLE_WERROR=ON"

            # # Currently broken. IDK if this is even useful though.
            # "-DLLVM_USE_STATIC_ZSTD=ON"

            "-DSYCL_ENABLE_EXTENSION_JIT=ON"
            "-DSYCL_ENABLE_MAJOR_RELEASE_PREVIEW_LIB=ON"
            "-DSYCL_ENABLE_WERROR=ON"
            "-DSYCL_BUILD_PI_HIP_PLATFORM=AMD"

            # (if pkgs.stdenv.cc.isClang then throw "hiii" else "")
          ]
          # ++ lib.optionals pkgs.stdenv.cc.isClang [
          #   # (lib.cmakeFeature "CMAKE_C_FLAGS_RELEASE" "-flto=thin\\\\ -ffat-lto-objects")
          #   # (lib.cmakeFeature "CMAKE_CXX_FLAGS_RELEASE" "-flto=thin\\\\ -ffat-lto-objects")
          #   "-DCMAKE_C_FLAGS_RELEASE=-flto=thin -ffat-lto-objects"
          #   "-DCMAKE_CXX_FLAGS_RELEASE=-flto=thin -ffat-lto-objects"
          # ]
          ++ lib.optional useLld (lib.cmakeFeature "LLVM_USE_LINKER" "lld")
          ++ unified-runtime'.cmakeFlags
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

    opencl-aot = stdenv.mkDerivation (finalAttrs: {
      pname = "opencl-aot";
      inherit version;
      src = runCommand "opencl-aot-src-${version}" {inherit (src) passthru;} ''
        mkdir -p "$out"
        cp -r ${src}/opencl "$out"
        # cp -r ${src}/cmake "$out"

        # chmod u+w "$out/opencl"
        mkdir -p "$out/cmake"
        cp -r ${src}/unified-runtime/cmake/FetchOpenCL.cmake "$out/cmake"

        # mkdir -p "$out/sycl/llvm/cmake"
        # mkdir -p "$out/llvm"
        # cp -r ${src}/llvm/cmake "$out/llvm"
        # cp -r ${src}/llvm/cmake/modules "$out/llvm/cmake/modules"
      '';
      # inherit src;
      #
      patches = [./opencl-aot.patch];

      sourceRoot = "${finalAttrs.src.name}/opencl";
      # sourceRoot = "${finalAttrs.src.name}/sycl";

      # outputs = [
      #   "out"
      #   "dev"
      #   "lib"
      # ];

      nativeBuildInputs = [cmake ninja];
      buildInputs = [overrides.llvm libffi zstd zlib libxml2];

      # nativeBuildInputs = [cmake ninja] ++ unified-runtime'.nativeBuildInputs;

      # buildInputs = [overrides.xpti] ++ unified-runtime'.buildInputs;

      cmakeFlags = [
        "-DLLVM_TARGETS_TO_BUILD=${targetsToBuild'}"
        "-DCMAKE_MODULE_PATH=${finalAttrs.src}/cmake"
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-HEADERS" "${deps.opencl-headers}")
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_OCL-ICD" "${deps.opencl-icd-loader}")
      ];
    });

    libclc =
      (llvmPkgs.libclc.override {
        # buildPackages.spirv-llvm-translator = null;
        llvm = overrides.llvm;
      }).overrideAttrs (old: {
        nativeBuildInputs = builtins.filter (x: !lib.strings.hasInfix "SPIRV-LLVM-Translator" (builtins.toString x)) old.nativeBuildInputs;
        # e = throw (lib.strings.concatStringsSep ";" (builtins.map (x: builtins.toJSON x) old.nativeBuildInputs));

        buildInputs = old.buildInputs ++ [zstd zlib];
      });

    # libclc = callPackage ./libclc {
    #   buildLlvmTools = llvmPkgs // overrides;
    #   getVersionFile = x: [];
    # };

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

      # patches = [./sycl.patch];
      postPatch = ''
        substituteInPlace ../sycl/CMakeLists.txt \
          --replace-fail 'message(FATAL_ERROR "opencl external project required but not found.")' 'find_package(OpenCL REQUIRED)'
      '';

      sourceRoot = "${finalAttrs.src.name}/llvm";
      # sourceRoot = "${finalAttrs.src.name}/sycl";

      nativeBuildInputs = [cmake ninja] ++ unified-runtime'.nativeBuildInputs;

      buildInputs = [overrides.xpti overrides.opencl-aot] ++ unified-runtime'.buildInputs;

      cmakeFlags =
        [
          # "-DLLVM_ENABLE_PROJECTS=sycl;opencl;xpti;xptifw;sycl-jit;libclc"
          "-DLLVM_ENABLE_PROJECTS=sycl;sycl-jit"

          "-DLLVM_EXTERNAL_PROJECTS=sycl;xpti;xptifw;sycl-jit"
          "-DLLVM_EXTERNAL_XPTI_SOURCE_DIR=/build/${finalAttrs.src.name}/xpti"

          "-DSYCL_ENABLE_XPTI_TRACING=ON"
          # "-DSYCL_ENABLE_BACKENDS=level_zero;level_zero_v2;cuda;hip"
          "-DSYCL_ENABLE_BACKENDS=${lib.strings.concatStringsSep ";" unified-runtime'.backends}"

          "-DSYCL_INCLUDE_TESTS=ON"

          "-DSYCL_ENABLE_WERROR=ON"

          "-DSYCL_ENABLE_EXTENSION_JIT=ON"
          "-DSYCL_ENABLE_MAJOR_RELEASE_PREVIEW_LIB=ON"
          "-DSYCL_ENABLE_WERROR=ON"
          "-DSYCL_BUILD_PI_HIP_PLATFORM=AMD"

          # Lookup broken
          (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_EMHASH" "${deps.emhash}")
          (lib.cmakeBool "SYCL_UR_USE_FETCH_CONTENT" false)
        ]
        ++ unified-runtime'.cmakeFlags;
    });

    clang-unwrapped = (llvmPkgs.clang-unwrapped.override {}).overrideAttrs (old: {
      buildInputs =
        (old.buildInputs or [])
        ++ [
          zstd
          zlib
          libedit
        ];

      cmakeFlags =
        (old.cmakeFlags or [])
        ++ [
          (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
          (lib.cmakeBool "FETCHCONTENT_QUIET" false)

          (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_VC-INTRINSICS" "${deps.vc-intrinsics}")
        ];
    });

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

    mkExtraBuildCommands0 = cc:
      ''
        rsrc="$out/resource-root"
        mkdir "$rsrc"
        echo "-resource-dir=$rsrc" >> $out/nix-support/cc-cflags
      ''
      # clang standard c headers are incompatible with FreeBSD so we have to put them in -idirafter instead of -resource-dir
      # see https://github.com/freebsd/freebsd-src/commit/f382bac49b1378da3c2dd66bf721beaa16b5d471
      + (
        if stdenv.targetPlatform.isFreeBSD
        then ''
          echo "-idirafter ${lib.getLib cc}/lib/clang/${lib.versions.major overrides.llvm.version}/include" >> $out/nix-support/cc-cflags
        ''
        else ''
          ln -s "${lib.getLib cc}/lib/clang/${lib.versions.major overrides.llvm.version}/include" "$rsrc"
        ''
      );

    mkExtraBuildCommands = cc:
      overrides.mkExtraBuildCommands0 cc
      + ''
        ln -s "${llvmPkgs.compiler-rt.out}/lib" "$rsrc/lib"
        ln -s "${llvmPkgs.compiler-rt.out}/share" "$rsrc/share"
      '';

    clangNoLibcNoRt = wrapCCWith rec {
      cc = overrides.clang-unwrapped;
      libcxx = null;
      bintools = llvmPkgs.bintoolsNoLibc;
      extraPackages = [];
      # "-nostartfiles" used to be needed for pkgsLLVM, causes problems so don't include it.
      extraBuildCommands = overrides.mkExtraBuildCommands0 cc;

      # "-nostartfiles" used to be needed for pkgsLLVM, causes problems so don't include it.
      nixSupport.cc-cflags = lib.optional (
        stdenv.targetPlatform.isWasm
      ) "-fno-exceptions";
    };

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
        # parallel-hashmap
        # emhash
        overrides.xpti
      ];

      # TODO
      cmakeFlags = [
        # Lookup broken
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_EMHASH" "${deps.emhash}")
        # Lookup not implemented
        (lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_PARALLEL-HASHMAP" "${parallel-hashmap.src}")

        (lib.cmakeBool "XPTI_ENABLE_WERROR" true)
      ];
    });

    # # Wrapper to fix LLVM CMake exports
    # llvm =
    #   runCommand "llvm-patched-${overrides.llvm-unpatched.version}" {
    #     outputs = ["out" "dev" "lib"];
    #     inherit (overrides.llvm-unpatched) version;
    #   } ''
    #           # Copy the original LLVM outputs
    #           cp -r ${overrides.llvm-unpatched} $out
    #           cp -r ${overrides.llvm-unpatched.dev} $dev
    #           cp -r ${overrides.llvm-unpatched.lib} $lib
    #           chmod -R u+w $dev $out $lib

    #           # Patch all text files (CMake, pkg-config) with store path references
    #           find $dev -type f \( -name "*.cmake" -o -name "*.pc" \) -exec sed -i \
    #             -e 's|${overrides.llvm-unpatched}|'$out'|g' \
    #             -e 's|${overrides.llvm-unpatched.dev}|'$dev'|g' \
    #             -e 's|${overrides.llvm-unpatched.lib}|'$lib'|g' \
    #             -e 's|/nix/store/g6kx2793pvvcw812n084d5rhz8l0y1nl-zstd-1.5.7-bin/include|${zstd}/include|g' \
    #             -e 's|/nix/store/wz37m8hfmpfg7zmmwjax5fvfsdzadf76-libedit-20250104-3.1/include|${libedit}/include|g' \
    #             {} +

    #           # Fix include paths that should point to dev output
    #           find $dev -type f \( -name "*.cmake" -o -name "*.pc" \) -exec sed -i \
    #             -e 's|'$out'/include|'$dev'/include|g' \
    #             -e 's|''${_IMPORT_PREFIX}/include|'$dev'/include|g' \
    #             {} +

    #           # Patch binary files (like llvm-config) with store path references
    #           find $dev/bin -type f -executable -exec sed -i \
    #             -e 's|${overrides.llvm-unpatched}|'$out'|g' \
    #             -e 's|${overrides.llvm-unpatched.dev}|'$dev'|g' \
    #             -e 's|${overrides.llvm-unpatched.lib}|'$lib'|g' \
    #             -e 's|'$out'/include|'$dev'/include|g' \
    #             {} + 2>/dev/null || true

    #           # Add missing dependency targets to LLVMConfig.cmake
    #           cat >> $dev/lib/cmake/llvm/LLVMConfig.cmake << EOF

    #     # Patched by Nix wrapper to fix missing dependencies
    #     if(NOT TARGET zstd::libzstd_shared)
    #       add_library(zstd::libzstd_shared SHARED IMPORTED)
    #       set_target_properties(zstd::libzstd_shared PROPERTIES
    #         IMPORTED_LOCATION "${zstd.out}/lib/libzstd.so"
    #         INTERFACE_INCLUDE_DIRECTORIES "${zstd.dev}/include"
    #       )
    #     endif()

    #     if(NOT TARGET LibEdit::LibEdit)
    #       add_library(LibEdit::LibEdit SHARED IMPORTED)
    #       set_target_properties(LibEdit::LibEdit PROPERTIES
    #         IMPORTED_LOCATION "${libedit}/lib/libedit.so"
    #         INTERFACE_INCLUDE_DIRECTORIES "${libedit.dev}/include"
    #       )
    #     endif()

    #     # Add dummy DeviceConfigFile target for SYCL extensions
    #     if(NOT TARGET DeviceConfigFile)
    #       add_custom_target(DeviceConfigFile)
    #     endif()
    #     EOF
    #   '';
    llvm = overrides.llvm-unpatched;
  };
in
  llvmPkgs // overrides
