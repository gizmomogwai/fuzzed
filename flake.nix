{
  description = "Fuzzed search library and terminal finder";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in {
      devShells = nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          compilerPackages = [ pkgs.ldc pkgs.dub pkgs.git ];
        in {
          default = pkgs.mkShell {
            packages = compilerPackages;
          };
        });
    };
}
