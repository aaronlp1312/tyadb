#!/data/data/com.termux/files/usr/bin/sh
set -eu

say() { printf '[tyadb installer] %s\n' "$*"; }
die() { say "ERROR: $*" >&2; exit 1; }

[ -n "${PREFIX:-}" ] || die "Run this inside Termux. Official app: https://f-droid.org/packages/com.termux/"
[ "${PREFIX}" = "/data/data/com.termux/files/usr" ] || die "Unsupported environment: PREFIX=$PREFIX (Termux is required)"

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PAYLOAD="$HERE/files"
[ -f "$PAYLOAD/tyadb" ] || die "Bundle is incomplete: files/tyadb is missing"
[ -d "$PAYLOAD/tyty-bin" ] || die "Bundle is incomplete: files/tyty-bin is missing"

say "Updating Termux package metadata"
pkg update -y

say "Installing required dependencies"
pkg install -y android-tools bash coreutils curl gawk grep iproute2 netcat-openbsd python sed

say "Installing optional helpers when available"
pkg install -y fzf termux-api >/dev/null 2>&1 || say "Optional fzf/termux-api install skipped"

DEST="$HOME/bin"
TYTY_DEST="$HOME/tydroid/tyty/bin"
mkdir -p "$DEST" "$TYTY_DEST" "$HOME/tydroid/config" "$HOME/environments/tyty-droid" "$HOME/.config/tydroid/adb" "$HOME/.local/state/tydroid/adb" "$HOME/.local/state/tydroid/logs" "$HOME/.tydroid/adb"

for src in "$PAYLOAD"/*; do
  [ -f "$src" ] || continue
  name=${src##*/}
  cp "$src" "$DEST/$name"
done
chmod 700 "$DEST"/tyadb "$DEST"/tyadb-* "$DEST"/tyadb-control.py

say "Installing the TyDroid command layer"
for src in "$PAYLOAD/tyty-bin"/*; do
  [ -f "$src" ] || continue
  name=${src##*/}
  cp "$src" "$TYTY_DEST/$name"
  chmod 700 "$TYTY_DEST/$name"
  ln -sf "$TYTY_DEST/$name" "$DEST/$name"
done

if [ ! -e "$HOME/tyadb.env" ]; then
  cp "$HERE/config/tyadb.env.example" "$HOME/tyadb.env"
  chmod 600 "$HOME/tyadb.env"
fi
cp "$HERE/config/tyadb.env.example" "$HOME/tydroid/config/tyadb.env"
cp "$HERE/config/tyty-adb.conf" "$HOME/tydroid/config/tyty-adb.conf"
cp "$HERE/README.md" "$DEST/.README.tyadb"
chmod 600 "$DEST/.README.tyadb"

case ":${PATH}:" in
  *":$HOME/bin:"*) ;;
  *)
    PROFILE="$HOME/.profile"
    printf '\n# tyadb commands\nexport PATH="$HOME/bin:$PATH"\n' >> "$PROFILE"
    say "Added ~/bin to PATH in ~/.profile"
    ;;
esac

say "Installed tyadb in $DEST"
say "Run: export PATH=\"$HOME/bin:$PATH\""
say "Then: tyadb doctor"
say "Wireless setup: tyadb pair HOST:PAIR_PORT CODE; tyadb connect HOST:CONNECT_PORT"
