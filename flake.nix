{
  description = "Snap package for Nix and NixOS";

  inputs.flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";

  outputs = { self, nixpkgs, flake-compat }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      buildFor = system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          packages.${system}.default = pkgs.callPackage ./src/package.nix { };
          nixosModules.default = import ./src/nixos-module.nix self;
          checks.${system}.test = import ./src/test.nix { inherit self pkgs; };
        };
    in
    builtins.foldl' (acc: system: acc // buildFor system) { } systems;
}
