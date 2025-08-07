{
  kit,
  stdenv,
  overrideCC,
  runCommand,
}:
overrideCC stdenv runCommand {
  name = "intel-todo";
  installPhase = ''
    # TODO: Use .version or similar
    ln -s ${kit}/2025.2 $out
  '';
}
