{
  description = "mdgen - generate markdown files from lean files";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Read version from lean-toolchain (e.g., "leanprover/lean4:v4.30.0-rc2")
      leanVersion = builtins.head
        (builtins.match "leanprover/lean4:v([^\n]+)\n?" (builtins.readFile ./lean-toolchain));

      # Read Cli dependency info from lake-manifest.json
      manifest = builtins.fromJSON (builtins.readFile ./lake-manifest.json);
      cliPkg = builtins.head (builtins.filter (p: p.name == "Cli") manifest.packages);

      # Read pre-computed toolchain hashes
      toolchainHashes = builtins.fromJSON (builtins.readFile ./nix/toolchain-hashes.json);

      platformSuffix = {
        x86_64-linux = "linux";
        aarch64-linux = "linux_aarch64";
        x86_64-darwin = "darwin";
        aarch64-darwin = "darwin_aarch64";
      };
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        suffix = platformSuffix.${system};

        lean-toolchain = pkgs.stdenv.mkDerivation {
          pname = "lean4-toolchain";
          version = leanVersion;

          src = pkgs.fetchurl {
            url = "https://github.com/leanprover/lean4/releases/download/v${leanVersion}/lean-${leanVersion}-${suffix}.tar.zst";
            hash = toolchainHashes.${suffix};
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
            cp -r lean-${leanVersion}-${suffix}/* $out/
          '';
        };

        cli-src = builtins.fetchGit {
          url = cliPkg.url;
          rev = cliPkg.rev;
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
            git remote add origin ${cliPkg.url}
            git add -A
            git -c user.name=nix -c user.email=nix@nix commit -q -m "nix"
            LOCAL_REV=$(git rev-parse HEAD)
            popd

            # Patch manifest so Lake sees the local commit as matching
            sed -i "s/${cliPkg.rev}/$LOCAL_REV/" lake-manifest.json

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
