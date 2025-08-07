{
  runCommand,
  llvm,
  version,
}:
runCommand "llvm-binutils-${version}"
{
  preferLocalBuild = true;
  passthru = {
    isLLVM = true;
    inherit llvm;
  };
}
''
  mkdir -p $out/bin
  for prog in ${llvm}/bin/*; do
    ln -s $prog $out/bin/$(basename $prog)
  done

  llvmBin="${llvm}/bin"

  ln -s $llvmBin/llvm-ar $out/bin/ar
  ln -s $llvmBin/llvm-ar $out/bin/dlltool
  ln -s $llvmBin/llvm-ar $out/bin/ranlib
  ln -s $llvmBin/llvm-cxxfilt $out/bin/c++filt
  ln -s $llvmBin/llvm-dwp $out/bin/dwp
  ln -s $llvmBin/llvm-nm $out/bin/nm
  ln -s $llvmBin/llvm-objcopy $out/bin/objcopy
  ln -s $llvmBin/llvm-objcopy $out/bin/strip
  ln -s $llvmBin/llvm-objdump $out/bin/objdump
  ln -s $llvmBin/llvm-readobj $out/bin/readelf
  ln -s $llvmBin/llvm-size $out/bin/size
  ln -s $llvmBin/llvm-strings $out/bin/strings
  ln -s $llvmBin/llvm-symbolizer $out/bin/addr2line

  if [ -e "$llvmBin/llvm-debuginfod" ]; then
    ln -s $llvmBin/llvm-debuginfod $out/bin/debuginfod
    ln -s $llvmBin/llvm-debuginfod-find $out/bin/debuginfod-find
  fi

  ln -s $llvmBin/lld $out/bin/ld

  ln -s $llvmBin/llvm-rc $out/bin/windres
''
