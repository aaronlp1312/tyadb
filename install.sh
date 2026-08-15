#!/data/data/com.termux/files/usr/bin/sh
set -eu

say() { printf '[tyadb installer] %s\n' "$*"; }
die() { say "ERROR: $*" >&2; exit 1; }

[ -n "${PREFIX:-}" ] || die "Run this inside Termux. Official app: https://f-droid.org/packages/com.termux/"
[ "${PREFIX}" = "/data/data/com.termux/files/usr" ] || die "Unsupported environment: PREFIX=$PREFIX (Termux is required)"

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PAYLOAD="$HERE/files"
[ -f "$PAYLOAD/tyadb" ] || die "Bundle is incomplete: files/tyadb is missing"

say "Updating Termux package metadata"
pkg update -y

say "Installing required dependencies"
pkg install -y android-tools bash coreutils curl gawk grep iproute2 netcat-openbsd python sed

say "Installing optional helpers when available"
pkg install -y fzf termux-api >/dev/null 2>&1 || say "Optional fzf/termux-api install skipped"

DEST="$HOME/bin"
mkdir -p "$DEST" "$HOME/.config/tydroid/adb" "$HOME/.local/state/tydroid/adb" "$HOME/.local/state/tydroid/logs" "$HOME/.tydroid/adb"

for src in "$PAYLOAD"/*; do
  [ -f "$src" ] || continue
  name=${src##*/}
  cp "$src" "$DEST/$name"
done
chmod 700 "$DEST"/tyadb "$DEST"/tyadb-* "$DEST"/tyadb-control.py
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

