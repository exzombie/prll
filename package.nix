{
  lib,
  stdenv,
  txt2man,
  bash,
  zsh,
  dash,
  coreutils,
  gnugrep,
  diffutils,
  unixtools,
}:

let
  version = lib.pipe (builtins.readFile ./Makefile) [
    (lib.splitString "\n")
    (lib.findFirst (lib.hasPrefix "PRLL_DEFAULT_VERSION") (
      throw "PRLL_DEFAULT_VERSION not found in Makefile"
    ))
    (builtins.match "PRLL_DEFAULT_VERSION[[:space:]]*=[[:space:]]*([0-9.]+).*")
    lib.head
  ];
in
stdenv.mkDerivation {
  pname = "prll";
  inherit version;

  src = ./.;

  nativeBuildInputs = [ txt2man ];

  buildPhase = ''
    runHook preBuild
    make compile
    runHook postBuild
  '';

  doCheck = true;
  nativeCheckInputs = [
    bash
    zsh
    dash
    coreutils
    gnugrep
    diffutils
    unixtools.ps
  ];
  checkPhase = ''
    runHook preCheck
    make test
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    make install PREFIX=$out ENV_DIR=$out/share/prll
    runHook postInstall
  '';

  meta = {
    description = "Parallelize a shell function or command string over a list of arguments using all CPU cores";
    homepage = "https://github.com/exzombie/prll";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.unix;
    maintainers = [ ];
  };
}
