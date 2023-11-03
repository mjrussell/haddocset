{
  description = "Provide an environment for working in this repo";

  # to handle mac and linux
  inputs.flake-utils.url = "github:numtide/flake-utils";

  # we want to use a consistent nixpkgs across developers.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = all@{ self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # https://github.com/NixOS/nixpkgs/issues/140774 reoccurs in GHC 9.4
        workaround140774 = hpkg: with pkgs.haskell.lib;
          overrideCabal hpkg (drv: {
            enableSeparateBinOutput = false;
          });
        # we want to replace the latest version of purescript with our specific version.
        # same with ghc
        overlay = (self: super: rec {
          # SET GHC VERSION HERE
          ghc = super.haskell.compiler.ghc96;
          ourHaskellPkgs = super.haskell.packages.ghc96;
          haskell = super.haskell;
        });

        # with our overlay done, make the final version of our nixpkgs
        pkgs = import nixpkgs {
          inherit system;
          overlays = [overlay];
        };
        # for convenience
        lib = nixpkgs.lib;

        # we don't want to use stack's nix integration, but
        # we do want to use the ghc we grab from nixpkgs instead
        # of having stack install another one
        stackWrapped = pkgs.symlinkJoin {
          name = "stack";
          buildInputs = [ pkgs.makeWrapper ];
          paths = [
            pkgs.stack
          ];
          postBuild = ''
              wrapProgram $out/bin/stack \
                --add-flags '--no-nix --system-ghc'
            '';
        };

        ghcid = if system == "aarch64-darwin"
                then workaround140774 pkgs.ourHaskellPkgs.ghcid
                else pkgs.ourHaskellPkgs.ghcid;

        packages =
          let
            # everything we want available in our development environment that isn't managed by
            # npm, spago, or stack.
            # we do not differentiate between libraries needed for building and tools at the moment.
            sharedPackages = with pkgs; [
              cabal-install
              ghc
              ghcid
              ncurses5
              pkg-config
              stackWrapped
              zlib
              # some of ubuntu 'build-essentials'
              coreutils
              gcc
              gnugrep
              gnused
              gnutar
              gzip
            ];
          in
            sharedPackages;

        # some silliness: we need to point stack to all of the include and lib directories
        # of our packages. we do this with extra-lib-dirs and extra-include-dirs, and we need
        # to make those long sets of flags. this makes those flags
        mkFlags = outputDir: subDir: flag: ps:
          lib.concatStringsSep " "
          (
          map
            (path: " ${flag}${path}/${subDir}")
            (lib.filter (x: x != null)
              (map (lib.getOutput outputDir) ps))
          );
        libFlags = mkFlags "lib" "lib" "--extra-lib-dirs=" packages;
        inclFlags = mkFlags "include" "include" "--extra-include-dirs=" packages;
      in {
        # produce our actual shell
        devShell = pkgs.mkShell rec {
          # these make stack play nice with our packages and be able to find them
          STACK_IN_NIX_EXTRA_ARGS = "${libFlags} ${inclFlags}";

          # make our packages available
          buildInputs = packages;
          # including the libraries
          LD_LIBRARY_PATH = lib.makeLibraryPath packages;
        };
      }) //
      {
    };
}

