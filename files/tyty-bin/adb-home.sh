#!/data/data/com.termux/files/usr/bin/bash
set -e

IP="${1:-${TYADB_HOME_IP:-}}"
CONNECT_PORT="${2:-${TYADB_HOME_CONNECT_PORT:-}}"
TCP_PORT="${3:-${TYADB_HOME_TCP_PORT:-5555}}"

[ -n "$IP" ] && [ -n "$CONNECT_PORT" ] || {
  echo "Usage: adb-home.sh IP CONNECT_PORT [TCP_PORT]" >&2
  exit 2
}

adb start-server >/dev/null 2>&1 || true
echo "[ADB] Connect → TCP"
adb connect ${IP}:${CONNECT_PORT} || true
adb -s ${IP}:${CONNECT_PORT} tcpip ${TCP_PORT} || true
sleep 1
adb connect ${IP}:${TCP_PORT} || true
echo "[ADB] Connected on ${IP}:${TCP_PORT}"
