{
  pkgs,
  homeManagerLib,
  hmModule,
  package,
}:

let
  mkHmConfig =
    shell:
    homeManagerLib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        hmModule
        {
          home.username = "prlltest";
          home.homeDirectory = "/home/prlltest";
          home.stateVersion = "26.05";

          programs.prll = {
            enable = true;
            inherit package;
            enableBashIntegration = shell == "bash";
            enableZshIntegration = shell == "zsh";
          };

          programs.bash.enable = shell == "bash";
          programs.zsh.enable = shell == "zsh";
        }
      ];
    };

  # Builds the HM activation's rendered dotfiles for `shell`, then both
  # statically asserts prll.sh is sourced and actually sources the rendered
  # rc file in a real, interactive instance of that shell and runs a
  # trivial job through prll -- proving the integration really works, not
  # just that a string was inserted somewhere.
  mkShellCheck =
    shell: rcFile: shellPkg:
    let
      homeFiles = (mkHmConfig shell).config.home-files;
    in
    pkgs.runCommand "prll-hm-${shell}-integration"
      {
        nativeBuildInputs = [ shellPkg ];
      }
      ''
        grep -q 'source .*/share/prll/prll.sh' '${homeFiles}/${rcFile}' \
          || { echo "prll.sh is not sourced in ${rcFile}"; exit 1; }

        export HOME=$(mktemp -d)
        ln -s '${homeFiles}/${rcFile}' "$HOME/${rcFile}"

        set +e
        output=$(
          ${shellPkg}/bin/${shell} -i -c '
            type prll >/dev/null 2>&1 || { echo "prll function not defined after sourcing ${rcFile}"; exit 1; }
            PRLL_NRJOBS=1 prll true a b c
          ' 2>&1
        )
        status=$?
        set -e

        echo "$output"
        [ "$status" -eq 0 ] || exit 1
        echo "$output" | grep -q finished \
          || { echo "prll did not report any finished job"; exit 1; }

        touch $out
      '';
in
{
  bash = mkShellCheck "bash" ".bashrc" pkgs.bash;
  zsh = mkShellCheck "zsh" ".zshrc" pkgs.zsh;
}
