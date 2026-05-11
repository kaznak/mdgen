{
  description = "mdgen - generate markdown files from lean files";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        leanVersion = "4.30.0-rc2";

        platformInfo = {
          x86_64-linux = {
            suffix = "linux";
            hash = "sha256-W1FiXxVPChOze9iS8dlfeen9W58NCVtBJiFe4ryNvoY=";
          };
          aarch64-linux = {
            suffix = "linux_aarch64";
            hash = "sha256-sZb0HaI5YOhC/A/AR0nRY51Eg5/q/AQU5Tyy22sWeQ8=";
          };
          x86_64-darwin = {
            suffix = "darwin";
            hash = "sha256-kqj9gZ002SDuWS8Ay449dEloLEsuQ6B2DCkhpuDn83A=";
          };
          aarch64-darwin = {
            suffix = "darwin_aarch64";
            hash = "sha256-aiPSYkH9eLzD0cJL6XNBv+P0Y18ub+q8u1hjA1KQqxs=";
          };
        }.${system};

        lean-toolchain = pkgs.stdenv.mkDerivation {
          pname = "lean4-toolchain";
          version = leanVersion;

          src = pkgs.fetchurl {
            url = "https://github.com/leanprover/lean4/releases/download/v${leanVersion}/lean-${leanVersion}-${platformInfo.suffix}.tar.zst";
            hash = platformInfo.hash;
          };

          nativeBuildInputs = [ pkgs.zstd ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
          buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            pkgs.glibc
            pkgs.gcc-unwrapped.lib
          ];

          sourceRoot = ".";

          unpackPhase = ''
            tar --zstd -xf $src
          '';

          installPhase = ''
            mkdir -p $out
            cp -r lean-${leanVersion}-${platformInfo.suffix}/* $out/
          '';
        };

        cli-src = builtins.fetchGit {
          url = "https://github.com/leanprover/lean4-cli.git";
          rev = "13567aed1ac4f12aea9484178e07e51f8c9f7658";
        };

      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "mdgen";
          version = leanVersion;

          src = pkgs.lib.cleanSource ./.;

          nativeBuildInputs = [ pkgs.git ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.autoPatchelfHook
            ];
          buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            pkgs.glibc
            pkgs.gcc-unwrapped.lib
          ];

          buildPhase = ''
            export HOME=$TMPDIR
            export PATH=${lean-toolchain}/bin:$PATH

            # Set up Cli dependency as a proper git repo so Lake recognizes it
            mkdir -p .lake/packages/Cli
            cp -r ${cli-src}/. .lake/packages/Cli/
            chmod -R u+w .lake/packages/Cli
            pushd .lake/packages/Cli
            git init -q
            git remote add origin https://github.com/leanprover/lean4-cli.git
            git add -A
            git -c user.name=nix -c user.email=nix@nix commit -q -m "nix"
            LOCAL_REV=$(git rev-parse HEAD)
            popd

            # Patch manifest so Lake sees the local commit as matching
            sed -i "s/13567aed1ac4f12aea9484178e07e51f8c9f7658/$LOCAL_REV/" lake-manifest.json

            lake build mdgen
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp .lake/build/bin/mdgen $out/bin/
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ lean-toolchain ];
        };
      }
    );
}
