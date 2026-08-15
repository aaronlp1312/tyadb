# tyadb portable bundle

This is an offline copy of the local tyadb command suite, packaged on
2026-07-18 for installation in Termux on another Android device.

## One-command install

Extract this archive in Termux, enter its directory, and run:

```sh
sh install.sh
```

The script installs dependencies with Termux `pkg`, copies the TyADB command
suite to `~/bin`, installs the associated TyDroid command layer to
`~/tydroid/tyty/bin`, creates config/state directories, and adds `~/bin` to
PATH when needed. Run `tyadb doctor` afterward.

The tyadb files themselves are included in `files/`, so they do not depend on
an external source repository. The package downloads require internet access.

## Required programs and official download links

- Termux: https://f-droid.org/packages/com.termux/
- Termux releases/source: https://github.com/termux/termux-app
- Termux packages: https://github.com/termux/termux-packages
- Android SDK Platform Tools / ADB: https://developer.android.com/tools/releases/platform-tools

Installed Termux packages:

- `android-tools`: `adb`
- `bash`: main script interpreter
- `coreutils`: `timeout`, `nohup`, and standard utilities
- `curl`: local Tydroid service health checks
- `gawk`, `grep`, `sed`: parsing and status output
- `iproute2`, `netcat-openbsd`: `tyadb-boot` Wi-Fi discovery and port tests
- `python`: optional `tyadb-control.py` HTTP control bridge

Optional packages:

- `fzf`: enhanced interactive `tyadb panel`
- `termux-api`: wake lock and Wi-Fi helpers. Its companion Android app is at
  https://f-droid.org/packages/com.termux.api/

Shizuku integration in `tyadb-boot` is optional and is used only when a
`shizuku` command already exists. Shizuku: https://shizuku.rikka.app/

Tasker integration is optional. Tasker: https://tasker.joaoapps.com/

## Included files

- `tyadb`: core ADB lifecycle, pairing, connection, status, watcher, and panel
- `tyadb-boot`: Wi-Fi reconnection/bootstrap helper
- `tyadb-control.py`: optional standard-library-only Python HTTP bridge
- `tyadb-*`: compatibility shortcut commands
- `files/tyty-bin/`: the `ty`, `ty-core`, `ty-install`, `tyty-adb-ctl`, bridge,
  WebTerm, and related command targets used by the symlinks in `~/bin`
- `config/`: portable `tyadb.env` and `tyty-adb.conf` templates
- `README.md`, `SHA256SUMS`, and `install.sh`

No ADB private keys, device IP addresses, serials, logs, or running PIDs are
included. Pair each new device normally through Android Wireless debugging.

## Manual verification

Before installing, from this directory:

```sh
sha256sum -c SHA256SUMS
```

After installing:

```sh
export PATH="$HOME/bin:$PATH"
tyadb doctor
tyadb help
tyty-adb-ctl status
```

The installer never copies your old pairing state, serials, logs, or ADB
private keys. Pair the secondary device normally through Android Wireless
debugging.
