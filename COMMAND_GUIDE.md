# tyadb README

`tyadb` is the Tydroid ADB command hub. It wraps `adb` with a Tydroid-owned
lifecycle, status/doctor output, saved connection state, and compatibility
shortcuts such as `tyadb-connect`, `tyadb-status`, and `tyadb-shell`.

The goal is to borrow useful automation shapes without copying any application
identifiers, package names, process names, service names, intent names, binder
interfaces, scripts, or error strings from other open-source Android tools.

## Files

Main command:

- `~/bin/tyadb`

Compatibility shortcuts:

- `~/bin/tyadb-auto`
- `~/bin/tyadb-connect`
- `~/bin/tyadb-devices`
- `~/bin/tyadb-doctor`
- `~/bin/tyadb-mdns`
- `~/bin/tyadb-pair`
- `~/bin/tyadb-panel`
- `~/bin/tyadb-ping`
- `~/bin/tyadb-info`
- `~/bin/tyadb-reconnect`
- `~/bin/tyadb-save-serial`
- `~/bin/tyadb-shell`
- `~/bin/tyadb-status`
- `~/bin/tyadb-tcpip`

Those shortcut files call `tyadb <subcommand>` so old muscle memory still works.

## State And Config

`tyadb` stores its own state under Tydroid paths:

- State: `~/.local/state/tydroid/adb`
- Config: `~/.config/tydroid/adb`
- Logs: `~/.local/state/tydroid/logs`
- Shared folder: `/storage/emulated/0/Download/Termux-shared`

Important state files:

- `~/.local/state/tydroid/adb/last_host`
- `~/.local/state/tydroid/adb/last_serial`
- `~/.local/state/tydroid/adb/session.env`
- `~/.local/state/tydroid/adb/status.env`

Optional shell allowlist:

- `~/.config/tydroid/adb/allowed-shell.txt`

## Environment Variables

You can override defaults with environment variables:

- `TYADB_ADB_BIN`: path to the `adb` binary
- `TYADB_HOME`: tyadb home folder
- `TYADB_STATE_DIR`: state folder
- `TYADB_CONFIG_DIR`: config folder
- `TYADB_LOG_DIR`: log folder
- `TYADB_SHARED_DIR`: Tasker/Termux shared folder
- `TYADB_BRIDGE_PORT`: Tydroid core API port, default `1313`
- `TYADB_UI_PORT`: Tydroid UI port, default `1312`
- `TYADB_DEFAULT_HOST`: fallback wireless ADB host
- `TYADB_REQUIRE_ALLOWLIST`: set to `1` to guard `tyadb shell`

Example:

```sh
TYADB_DEFAULT_HOST=192.0.2.50:5555 tyadb connect
```

## Main Commands

Show help:

```sh
tyadb help
```

Diagnose the setup:

```sh
tyadb doctor
tyadb-doctor
```

Show current state:

```sh
tyadb status
tyadb-status
```

Fast health check:

```sh
tyadb ping
tyadb-ping
```

Example output:

```text
[tyadb]
Server: running
Device: connected
Serial: 192.0.2.14:5555
Latency: 4 ms
Transport: tcpip
```

Script-friendly device summary:

```sh
tyadb info
tyadb-info
```

Example output:

```text
Host:    192.0.2.14:5555
Serial:  192.0.2.14:5555
State:   device
Battery: 82%
Android: 16
Model:   Pixel 8a
```

Persistent session watcher:

```sh
tyadb watch
tyadb-watch
```

By default, `tyadb watch` starts a detached background watcher. It polls every
few seconds, keeps `session.env` current, reconnects to the saved host when the
transport drops, tries mDNS when the device appears on a new wireless debugging
port, and logs connection transitions.

Watcher controls:

```sh
tyadb watch start [interval]
tyadb watch run [interval]
tyadb watch once
tyadb watch status
tyadb watch restart [interval]
tyadb watch stop
```

Notes:

- `start` runs in the background and records a PID.
- `run` stays in the foreground.
- `once` performs one repair/check cycle.
- `stop` releases the Termux wake lock when available.
- Logs go to `~/.local/state/tydroid/logs/tyadb.log`.

Start, stop, or restart the ADB server:

```sh
tyadb start
tyadb stop
tyadb restart
```

List devices:

```sh
tyadb devices
tyadb-devices
```

Show mDNS wireless debugging services:

```sh
tyadb mdns
tyadb-mdns
```

## Pairing And Connecting

Pair a wireless debugging session:

```sh
tyadb pair <host:pair_port> <pairing_code>
tyadb-pair <host:pair_port> <pairing_code>
```

Connect to a device:

```sh
tyadb connect <host:5555>
tyadb-connect <host:5555>
```

If the connection works, `tyadb` saves the host to:

```text
~/.local/state/tydroid/adb/last_host
```

Reconnect to the saved host:

```sh
tyadb reconnect
tyadb-reconnect
```

Save the currently connected serial:

```sh
tyadb save-serial
tyadb-save-serial
```

The serial is saved to:

```text
~/.local/state/tydroid/adb/last_serial
```

## Session File

Successful `connect`, `reconnect`, `auto`, `ping`, `info`, and `save-serial`
operations write a machine-readable session file:

```text
~/.local/state/tydroid/adb/session.env
```

Example:

```sh
TYADB_HOST=192.0.2.14
TYADB_PORT=5555
TYADB_SERIAL=192.0.2.14:5555
TYADB_CONNECTED=1
TYADB_LAST_CONNECT=2026-06-11T14:32:55Z
TYADB_LAST_CONNECT_EPOCH=1781242452
TYADB_PROTOCOL=tcpip
TYADB_STATE=device
```

Other scripts can load it directly:

```sh
. "$HOME/.local/state/tydroid/adb/session.env"
```

## Shell Usage

Open an interactive shell:

```sh
tyadb shell
tyadb-shell
```

Run a shell command:

```sh
tyadb shell id
tyadb shell settings get global adb_enabled
```

To require an allowlist before `tyadb shell <cmd>` can run:

```sh
TYADB_REQUIRE_ALLOWLIST=1 tyadb shell id
```

Allowlist file:

```text
~/.config/tydroid/adb/allowed-shell.txt
```

Each line can be either the first command word or a full command string.

Example:

```text
id
settings get global adb_enabled
pm list packages
```

## Auto Connect Flow

`tyadb auto` is for the common wireless ADB flow:

```sh
tyadb auto <host> [from_port] [tcpip_port]
tyadb-auto <host> [from_port] [tcpip_port]
```

Default ports:

- Initial/from port: `40459`
- TCP/IP port: `5555`

It attempts:

```text
connect host:from_port
wait
tcpip tcpip_port
disconnect old transport
connect host:tcpip_port
verify shell
save last_host
save serial
write session.env
```

If verification fails, `auto` disconnects the new transport and tries to reconnect
the old transport instead of saving bad state.

## Panel

Open a small menu:

```sh
tyadb panel
tyadb-panel
```

If `fzf` exists, it uses an interactive picker. Otherwise it shows a numbered
terminal menu.

## Status Output

`tyadb status` reports:

- ADB binary path
- ADB server state
- connection state
- transport type
- current host
- current serial
- device state
- connected device count
- last successful connection age
- allowlist state
- watcher state
- Tydroid core API status on port `1313`
- Tydroid UI status on port `1312`
- session file path
- state directory
- shared directory
- `adb devices -l`

`tyadb doctor` adds:

- `adb version`
- state/config/shared folder checks
- mDNS service output
- next actions

## Error Style

`tyadb` uses stable, searchable messages:

```text
[tyadb] adb missing: install android-tools or set TYADB_ADB_BIN
[tyadb] connect failed: usage: tyadb connect <host[:port]>
[tyadb] reconnect failed: no saved host; run tyadb connect <host:5555>
[tyadb] save serial skipped: no connected device
[tyadb] command denied: not in allowlist: <command>
[tyadb] connect failed: transport did not verify: <host:port>
```

## Clean-Room Rules

Allowed:

- Study lifecycle shapes.
- Study how tools separate start/stop/status/pair/connect/shell.
- Study permission checks, failure stages, and diagnostic messages.
- Build Tydroid-owned commands, state files, and names.

Not allowed:

- Copy package names.
- Copy application IDs.
- Copy process names.
- Copy service/action/binder identifiers.
- Copy scripts 1:1.
- Copy exact environment variable names from another app.
- Copy exact native loader paths from another app.
- Copy exact error messages.

## Recommended First Run

Run:

```sh
tyadb doctor
```

Then pair and connect:

```sh
tyadb pair <host:pair_port> <pairing_code>
tyadb connect <host:5555>
tyadb save-serial
tyadb status
```

After that, reconnect should be enough:

```sh
tyadb reconnect
```
