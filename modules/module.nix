moduleConfig:
{ lib, pkgs, config, ... }:

with lib;

{
  options.services.nixos-vscode-server = with types;{
    enable = mkEnableOption "auto-fix service for vscode-server in NixOS";
    nodePackage = mkOption {
      type = package;
      default = pkgs.nodejs-14_x;
    };
    ripPackage = mkOption {
      type = package;
      default = pkgs.ripgrep;
    };
    findPackage = mkOption {
      type = package;
      default = pkgs.findutils;
    };
  };

  config =
    let
      cfg = config.services.nixos-vscode-server;
      nodePath = "${cfg.nodePackage}/bin/node";
      findPath = "${cfg.findPackage}/bin/find";
      ripPath = "${cfg.ripPackage}/bin/rg";
      mkStartScript = name: pkgs.writeShellScript "${name}.sh" ''
        set -euo pipefail
        PATH=${makeBinPath (with pkgs; [ coreutils inotify-tools ])}
        bin_dir=~/.vscode-server/bin
        bin_dir2=~/.vscode-server-insiders/bin
        if [[ -e $bin_dir ]]; then
          ${findPath} "$bin_dir" -mindepth 2 -maxdepth 2 -name node -type f -exec ln -sfT ${nodePath} {} \;
          ${findPath} "$bin_dir" -path '*/vscode-ripgrep/bin/rg' -exec ln -sfT ${ripPath} {} \;
          ${findPath} "$bin_dir2" -mindepth 2 -maxdepth 2 -name node -type f -exec ln -sfT ${nodePath} {} \;
          ${findPath} "$bin_dir2" -path '*/vscode-ripgrep/bin/rg' -exec ln -sfT ${ripPath} {} \;
        else
          mkdir -p "$bin_dir"
          while IFS=: read -r bin_dir event; do
            # A new version of the VS Code Server is being created.
            if [[ $event == 'CREATE,ISDIR' ]]; then
              # Create a trigger to know when their node is being created and replace it for our symlink.
              touch "$bin_dir/node"
              inotifywait -qq -e DELETE_SELF "$bin_dir/node"
              ln -sfT ${nodePath} "$bin_dir/node"
              ln -sfT ${ripPath} "$bin_dir/node_modules/vscode-ripgrep/bin/rg"
            # The monitored directory is deleted, e.g. when "Uninstall VS Code Server from Host" has been run.
            elif [[ $event == DELETE_SELF ]]; then
              # See the comments above Restart in the service config.
              exit 0
            fi
          done < <(inotifywait -q -m -e CREATE,ISDIR -e DELETE_SELF --format '%w%f:%e' "$bin_dir")
        fi
      '';
    in
      mkIf cfg.enable (
        moduleConfig rec {
          name = "nixos-vscode-server";
          description = "Automatically fix the VS Code server used by the remote SSH extension";
          serviceConfig = {
            # When a monitored directory is deleted, it will stop being monitored.
            # Even if it is later recreated it will not restart monitoring it.
            # Unfortunately the monitor does not kill itself when it stops monitoring,
            # so rather than creating our own restart mechanism, we leverage systemd to do this for us.
            Restart = "always";
            RestartSec = 0;
            ExecStart = "${mkStartScript name}";
          };
        }
      );
}
