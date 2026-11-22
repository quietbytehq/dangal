#!/usr/bin/env bash
# Turn the Godot exports into release packages:
#   Linux:   Dangal-<ver>-x86_64.AppImage and dangal_<ver>_amd64.deb
#   Windows: Dangal-<ver>-Setup.exe
# usage: packaging/build_packages.sh <version without v> <out dir>
# expects build/linux/Dangal.x86_64 and build/windows/Dangal.exe (+ LICENSE etc.)
set -euo pipefail
VER="$1"; OUT="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
P="$ROOT/packaging"
mkdir -p "$OUT"
WORK="$(mktemp -d)"

# ---------- .deb
D="$WORK/deb"
mkdir -p "$D/DEBIAN" "$D/opt/dangal" "$D/usr/bin" "$D/usr/share/applications" \
         "$D/usr/share/icons/hicolor/256x256/apps" "$D/usr/share/doc/dangal"
cp -r "$ROOT"/build/linux/. "$D/opt/dangal/"
chmod 755 "$D/opt/dangal/Dangal.x86_64"
cat > "$D/usr/bin/dangal" <<'SH'
#!/bin/sh
exec /opt/dangal/Dangal.x86_64 "$@"
SH
chmod 755 "$D/usr/bin/dangal"
cp "$P/dangal.desktop" "$D/usr/share/applications/"
cp "$P/dangal.png" "$D/usr/share/icons/hicolor/256x256/apps/dangal.png"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$D/usr/share/doc/dangal/"
SIZE=$(du -sk "$D" | cut -f1)
cat > "$D/DEBIAN/control" <<CTL
Package: dangal
Version: $VER
Section: games
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Depends: libc6, libx11-6, libxcursor1, libxinerama1, libxrandr2, libxi6, libgl1
Recommends: libpulse0 | libasound2t64 | libasound2
Maintainer: Quiet Byte <quietbyte.2026@gmail.com>
Homepage: https://github.com/quietbytehq/dangal
Description: Dangal - 2D arcade fighting game
 Rustam of Karachi vs Baba Sher of Hunza. Two fighters, two animated stages,
 specials, ultras, full voice acting and breakable stage props.
 Keyboard and joypad.
CTL
dpkg-deb --root-owner-group --build "$D" "$OUT/dangal_${VER}_amd64.deb"

# ---------- AppImage
A="$WORK/Dangal.AppDir"
mkdir -p "$A/usr/bin"
cp -r "$ROOT"/build/linux/. "$A/usr/bin/"
chmod 755 "$A/usr/bin/Dangal.x86_64"
cat > "$A/AppRun" <<'SH'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/Dangal.x86_64" "$@"
SH
chmod 755 "$A/AppRun"
cp "$P/dangal.desktop" "$A/"
cp "$P/dangal.png" "$A/dangal.png"
cp "$P/dangal.png" "$A/.DirIcon"
TOOL="$WORK/appimagetool"
curl -fsSL -o "$TOOL" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x "$TOOL"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream "$A" "$OUT/Dangal-${VER}-x86_64.AppImage"

# ---------- Windows installer
cp "$P/dangal.ico" "$P/installer.nsi" "$WORK/"
mkdir -p "$WORK/win"
cp -r "$ROOT"/build/windows/. "$WORK/win/"
(cd "$WORK" && makensis -V2 -DVERSION="$VER" -DSRC=win -DOUT="$OUT/Dangal-${VER}-Setup.exe" installer.nsi)

rm -rf "$WORK"
ls -la "$OUT"
