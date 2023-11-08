{ pkgs ? import <nixpkgs> { } }:

let
  version = "2.61";
  src = pkgs.fetchFromGitHub {
    owner = "snapcore";
    repo = "snapd";
    rev = version;
    hash = "sha256-xxPqKeFujM4hL0LW0PLG2ojL9fhEsYrj9qTr9iVDvRw=";
  };
  goModules = (pkgs.buildGoModule {
    pname = "snap-go-mod";
    inherit version src;
    vendorHash = "sha256-DuvmnYl6ATBknSNzTCCyzYlLA0h+qo7ZmAED0mwIJkY=";
  }).goModules;

  snap = pkgs.stdenv.mkDerivation {
    pname = "snap";
    inherit version src;

    nativeBuildInputs = with pkgs; [
      makeWrapper
      autoconf
      automake
      autoconf-archive
    ];

    buildInputs = with pkgs; [
      go
      glibc
      glibc.static
      pkg-config
      libseccomp
      libxfs
      libcap
      glib
      udev
    ];

    patchPhase = ''
      substituteInPlace dirs/dirs.go \
        --replace '"/etc/systemd/system"' '"/run/systemd/system"' \
        --replace '"/etc/dbus-1/system.d"' '"/tmp/snap-dbus-system"' \
        --replace '"/etc/udev/rules.d"' '"/tmp/snap-udev-rules"' \
        --replace '"/usr/lib/snapd")' "\"$out/libexec/snapd\")"
      substituteInPlace systemd/systemd.go \
        --replace '--no-reload' '--runtime'
      substituteInPlace wrappers/binaries.go \
        --replace '"/usr/bin/snap"' "\"$out/bin/snap\""
      # TODO: add setuid wrapper
      substituteInPlace cmd/Makefile.am \
        --replace ' 4755 ' ' 755 ' \
        --replace 'install -d -m 755 $(DESTDIR)/var/lib/snapd/apparmor/snap-confine/' 'true' \
        --replace 'install -d -m 111 $(DESTDIR)/var/lib/snapd/void' 'true'
      substituteInPlace cmd/libsnap-confine-private/utils.c \
        --replace 'status == 0' '1'
      substituteInPlace cmd/snap-confine/mount-support.c \
        --replace '"/usr/src"' '"/usr/src",.is_optional = true'
    '';

    configurePhase = ''
      export GOCACHE=$TMPDIR/go-cache

      ln -s ${goModules} vendor

      ./mkversion.sh $version

      (
        cd cmd
        autoreconf -i -f
        ./configure \
          --prefix=$out \
          --libexecdir=$out/libexec/snapd \
          --with-snap-mount-dir=/snap \
          --disable-apparmor \
          --enable-nvidia-biarch \
          --enable-merged-usr
      )

      mkdir build
      cd build
    '';

    makeFlagsPackaging = [
      "--makefile=../packaging/snapd.mk"
      "SNAPD_DEFINES_DIR=${pkgs.writeTextDir "snapd.defines.mk" ""}"
      "snap_mount_dir=$(out)/snap"
      "bindir=$(out)/bin"
      "sbindir=$(out)/sbin"
      "libexecdir=$(out)/libexec"
      "mandir=$(out)/share/man"
      "datadir=$(out)/share"
      "localstatedir=$(TMPDIR)/localstatedir"
      "sharedstatedir=$(TMPDIR)/sharedstatedir"
      "unitdir=$(out)/unitdir"
      "builddir=."
      "with_testkeys=1"
      "with_apparmor=0"
      "with_core_bits=0"
      "with_alt_snap_mount_dir=0"
    ];

    makeFlagsData = [
      "--directory=../data"
      "BINDIR=$(out)/bin"
      "LIBEXECDIR=$(out)/libexec"
      "DATADIR=$(out)/share"
      "SYSTEMDSYSTEMUNITDIR=$(out)/etc/systemd/system"
      "SYSTEMDUSERUNITDIR=$(out)/etc/systemd/user"
      "ENVD=$(out)/etc/profile.d"
      "DBUSDIR=$(out)/share/dbus-1"
      "APPLICATIONSDIR=$(out)/share/applications"
      "SYSCONFXDGAUTOSTARTDIR=$(out)/etc/xdg/autostart"
      "ICON_FOLDER=$(out)/share/snapd"
    ];

    makeFlagsCmd = [
      "--directory=../cmd"
      "SYSTEMD_SYSTEM_GENERATOR_DIR=$out/lib/systemd/system-generators"
    ];

    buildPhase = ''
      make $makeFlagsPackaging all
      make $makeFlagsData all
      make $makeFlagsCmd all
    '';

    installPhase = ''
      make $makeFlagsPackaging install
      make $makeFlagsData install
      make $makeFlagsCmd install
    '';

    postFixup = ''
      wrapProgram $out/libexec/snapd/snapd --set SNAPD_DEBUG 1 --set PATH $out/bin:${
        pkgs.lib.makeBinPath
        (with pkgs; [ util-linux.mount squashfsTools systemd openssh ])
      }
    '';
  };

in snap
