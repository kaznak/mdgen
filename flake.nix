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

      # Read lake-manifest.json for dependency info
      manifest = builtins.fromJSON (builtins.readFile ./lake-manifest.json);

      # Fetch all git dependencies from the manifest
      depSources = builtins.listToAttrs (map (pkg: {
        name = pkg.name;
        value = builtins.fetchGit {
          url = pkg.url;
          rev = pkg.rev;
        };
      }) (builtins.filter (pkg: pkg.type == "git") manifest.packages));

      # Generate a replacement manifest with all deps converted to local paths
      overrideManifest = manifest // {
        packages = map (pkg: {
          inherit (pkg) name;
          inherited = pkg.inherited or false;
          type = "path";
          dir = ".lake/packages/${pkg.name}";
        }) manifest.packages;
      };

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

        # Write the override manifest as a JSON file in the nix store
        overrideManifestJson = pkgs.writeText "package-overrides.json"
          (builtins.toJSON overrideManifest);

        # Shell commands to set up all dependencies
        setupDepsScript = builtins.concatStringsSep "\n" (
          pkgs.lib.mapAttrsToList (name: src: ''
            cp -r ${src} .lake/packages/${name}
            chmod -R u+w .lake/packages/${name}
          '') depSources
        );

      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "mdgen";
          version = leanVersion;

          src = pkgs.lib.cleanSource ./.;

          nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            pkgs.autoPatchelfHook
          ];
          buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            pkgs.glibc
            pkgs.gcc-unwrapped.lib
          ];

          buildPhase = ''
            export HOME=$TMPDIR
            export PATH=${lean-toolchain}/bin:$PATH

            # Set up all dependencies from lake-manifest.json as local paths
            mkdir -p .lake/packages
            ${setupDepsScript}

            # Override manifest so Lake uses local path dependencies
            ln -sf ${overrideManifestJson} .lake/package-overrides.json

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
