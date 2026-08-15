#!/data/data/com.termux/files/usr/bin/bash
# adb-tlns-restart.sh
# Kill adb server, reconnect to the saved TLS endpoint via mDNS discovery,
# then optionally switch to tcpip 5555 and reconnect there.

IP="${1:-}"           # optional: pass IP to skip mDNS
JUMP_TO_5555="${JUMP_TO_5555:-1}"  # set 0 to skip tcpip hop

ts(){ date '+%Y-%m-%d %H:%M:%S'; }
log(){ echo "[tlns] $(ts) $*"; }

pick_mdns() {
  local kind="$1"
  # _adb-tls-connect._tcp is the connect service
  adb mdns services 2>/dev/null | awk -v k="$kind" '$0 ~ k {print $NF}' | head -n1
}

adb kill-server >/dev/null 2>&1 || true

# 1) find the current TLS connect endpoint host:port
if [ -z "$IP" ]; then
  ep="$(pick_mdns '_adb-tls-connect._tcp')"
  if [ -z "$ep" ]; then
    log "no TLS connect service found; turn on Wireless debugging"
    exit 2
  fi
  HOST="${ep%:*}"
  PORT="${ep##*:}"
else
  # discover port when only IP provided
  ep="$(pick_mdns '_adb-tls-connect._tcp')"
  if [ -n "$ep" ] && [ "${ep%:*}" = "$IP" ]; then
    HOST="$IP"
    PORT="${ep##*:}"
  else
    # fallback: require connect port
    log "no mDNS for $IP; need connect port"
    read -p "Connect port: " PORT
    HOST="$IP"
  fi
fi

CONNECT_EP="${HOST}:${PORT}"
log "connecting to ${CONNECT_EP}"
if ! adb connect "${CONNECT_EP}"; then
  log "connect failed; ensure device shows Wireless debugging and you're already paired"
  exit 3
fi

log "connected: ${CONNECT_EP}"

# 2) optional hop to classic tcpip :5555
if [ "$JUMP_TO_5555" = "1" ]; then
  if [ "$PORT" != "5555" ]; then
    log "switching adbd to tcpip 5555"
    if adb -s "${CONNECT_EP}" tcpip 5555; then
      sleep 1
      log "reconnecting to ${HOST}:5555"
      adb connect "${HOST}:5555" || log "reconnect on 5555 failed; staying on TLS port ${CONNECT_EP}"
    else
      log "tcpip 5555 not honored on this build; staying on TLS ${CONNECT_EP}"
    fi
  else
    log "already on 5555"
  fi
fi

log "devices:"
adb devices
