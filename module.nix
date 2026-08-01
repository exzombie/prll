{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.prll;
in
{
  options.programs.prll = {
    enable = lib.mkEnableOption "prll, a POSIX shell function for parallelizing tasks over multiple CPU cores";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage <prll/package.nix> { }";
      description = "The prll package to use.";
    };

    enableBashIntegration = lib.hm.shell.mkBashIntegrationOption { inherit config; };

    enableZshIntegration = lib.hm.shell.mkZshIntegrationOption { inherit config; };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # prll.sh only works in POSIX-function shells (bash, zsh); fish, ion and
    # nushell have incompatible function/scripting syntax and can't source it.

    # prll.sh only defines a shell function; it has no ordering requirement
    # relative to completion, aliases, prompts, etc., so it just needs to
    # load after the (unordered) defaults -- hence mkAfter, not a specific
    # hand-picked position.

    programs.bash.initExtra = lib.mkIf cfg.enableBashIntegration (
      lib.mkAfter ''
        source ${cfg.package}/share/prll/prll.sh
      ''
    );

    programs.zsh.initContent = lib.mkIf cfg.enableZshIntegration (
      lib.mkAfter ''
        source ${cfg.package}/share/prll/prll.sh
      ''
    );
  };
}
