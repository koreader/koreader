let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.05";
  pkgs = import nixpkgs { config = {}; overlays = []; };
in

pkgs.mkShell {
  packages = with pkgs; [
    autoconf
    automake
    cmake
    gcc
    gettext
    git
    gnumake
    gnupatch
    libtool
    meson
    nasm
    ninja
    perl
    pkg-config
    python3
    sdl3
    unzip
    wget
    # optional
    ccache
    luajit
    luajitPackages.luacheck
    p7zip
    shellcheck
    shfmt
  ];

  shellHook = ''
    export LD_LIBRARY_PATH=${pkgs.sdl3}/lib:$LD_LIBRARY_PATH
  '';
}
