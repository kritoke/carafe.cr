{
  description = "carafe.cr Spoke - crystal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    openspec.url = "github:Fission-AI/OpenSpec";
  };

  outputs = { self, nixpkgs, openspec }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      
                          { if (match($0,/^[[:space:]]*([a-zA-Z0-9_]+)[[:space:]]*=/)) {printing=1; buf=$0"
      "; next} if (printing) {buf=buf $0"
      "; if ($0 ~ /^[[:space:]]*};[[:space:]]*$/) {print buf; printing=0; buf=""}} }
      # Local package aliases
      let
        crystal_1_18_2 = crystal_1_18_2;
        buildInputs = buildInputs;
      in

      # System-specific Xorg libraries for Playwright
      # The `xorg` attribute set is deprecated in nixpkgs; prefer modern attribute names.
      # Map legacy names (libX...) to modern names (libx...) and try both.
      getXorg = name:
        let alt = builtins.replaceStrings [ "libX" ] [ "libx" ] name;
        in if builtins.hasAttr alt pkgs then builtins.getAttr alt pkgs else if builtins.hasAttr name pkgs then builtins.getAttr name pkgs else null;

      # Playwright libs removed from default spoke; include only when explicitly requested in a module.
      pwLibs = with pkgs; [];
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [ ] ++ pwLibs;

        shellHook = ''
          # --- Common Spoke Setup ---
          export HUB_ROOT="/workspaces/aiworkflow"
          if [ -S "/workspaces/aiworkflow/.ssh-auth.sock" ]; then
            export SSH_AUTH_SOCK="/workspaces/aiworkflow/.ssh-auth.sock"
          fi
          export PATH="$PATH:$HUB_ROOT/bin"
          export OPEN_SPEC_SKILLS_PATH="$HUB_ROOT/skills"
          export OPEN_SPEC_PROJECT_DIR="/workspaces/carafe.cr"
          
          echo "carafe.cr DevShell Active"
         '';
      };
    };
}
