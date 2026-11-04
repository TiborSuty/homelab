{ pkgs, pnpmVersion ? "12.3.4" }:
let
  # Match frontend-monorepo/.nvmrc and package.json, independently of nixpkgs.
  target = {
    x86_64-linux = {
      arch = "x64";
      hash = "sha256-55hZlhL0u3EzOjOXqw0JX9YiFOEVrqRaqFihRfxy1n4=";
      pnpmHash = "sha512-2ZqOlSPkfwX1h5cR+FPiWf8+F+2hZT/3TvhUK5sigHqwaQCIiq8R7CGxhndKs63JtcLi2a1Qpo+wX/EoyfjyJQ==";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-qogRUb0PnxVKBCTdYKcunOEGcmGRIWWMJ4okMn70aDE=";
      pnpmHash = "sha512-t71AVA7LRqiKTyZ5xMYaZc2n5DfdpMbfokZuiIOXHBOM03ECnF0t4iYwaBDqJgVjlKYUOwaF/bRQajGNA4cJ4w==";
    };
  }.${pkgs.stdenv.hostPlatform.system};
  node = pkgs.stdenvNoCC.mkDerivation {
    pname = "workspace-nodejs";
    version = "24.13.0";
    src = pkgs.fetchurl {
      url = "https://nodejs.org/dist/v24.13.0/node-v24.13.0-linux-${target.arch}.tar.xz";
      inherit (target) hash;
    };
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];
    installPhase = ''
      mkdir -p "$out"
      cp -r bin include lib share "$out/"
    '';
  };
  pnpm = pkgs.stdenvNoCC.mkDerivation {
    pname = "workspace-pnpm";
    version = pnpmVersion;
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/pnpm/-/pnpm-${pnpmVersion}.tgz";
      hash = {
        "12.3.4" = "sha512-lhqkH7B32joEpEHZ+OFevAyW2o73ELLrZ7+e58sGEOq9SPH9hfUc/+c4RnhfoPh8VqOocqHYk/hEZ0G1zORUVw==";
        "11.22.0" = "sha512-H/hwxMYTPf2I+yr8Rt0T1H8JyXlLQ4xv20fKmMrzvBY4HuC+k6CRuOOCTPAfiJ9G19niCRD7C+GrD7W6qA3WIQ==";
      }.${pnpmVersion};
    };
    nativeBinary = if pnpmVersion == "12.3.4" then pkgs.fetchurl {
      url = "https://registry.npmjs.org/@pnpm/exe.linux-${target.arch}/-/exe.linux-${target.arch}-12.3.4.tgz";
      hash = target.pnpmHash;
    } else null;
    nativeBuildInputs = [ pkgs.makeWrapper pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.openssl pkgs.zlib ];
    installPhase = ''
      mkdir -p "$out/lib/pnpm" "$out/bin"
      cp -r . "$out/lib/pnpm/"
    '' + (if pnpmVersion == "12.3.4" then ''
      tar -xzf "$nativeBinary" -C "$out/lib/pnpm" --strip-components=1 package/pnpm
      chmod +x "$out/lib/pnpm/pnpm"
      makeWrapper "$out/lib/pnpm/pnpm" "$out/bin/pnpm" --prefix PATH : ${node}/bin
    '' else ''
      makeWrapper ${node}/bin/node "$out/bin/pnpm" --add-flags "$out/lib/pnpm/bin/pnpm.mjs"
    '');
  };
in [ node pnpm pkgs.python3 pkgs.gnumake pkgs.gcc ]
