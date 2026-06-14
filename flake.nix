{
  description = "carafe.cr - Crystal project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    openspec.url = "github:Fission-AI/OpenSpec";
  };

  outputs = { self, nixpkgs, flake-utils, openspec }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            crystal
            shards
            openspec.packages.${system}.default
          ];

          shellHook = ''
            echo "carafe.cr DevShell Active"
          '';
        };
      }
    );
}
