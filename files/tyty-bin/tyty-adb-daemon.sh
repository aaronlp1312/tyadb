#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

TYDROID_ROOT="${TYDROID_ROOT:-$HOME/tydroid}"
ENV_FILE="${TYADB_ENV:-$HOME/tyadb.env}"
[ -r "$ENV_FILE" ] || ENV_FILE="$TYDROID_ROOT/config/tyadb.env"
# shellcheck source=/dev/null
. "$ENV_FILE"

CONF="${TYADB_DAEMON_CONF:-$TYDROID_ROOT/config/tyty-adb.conf}"
LOG="${TYADB_DAEMON_LOG:-$HOME/.local/state/tyadb/tyadb-daemon.log}"
STDIR="${TYADB_STATE_DIR:-$HOME/.config/tyadb}"
ST="$STDIR/last_endpoint"
PID="$STDIR/tyadb-daemon.pid"
LEGACY_ST="$STDIR/legacy-tyty-adb.state"
mkdir -p "$STDIR" "$(dirname "$LOG")"

ts(){ date '+%F %T'; }
rot(){
  local max=$(( ${MAX_LOG_SIZE:-10} * 1024 * 1024 ))
  [ -f "$LOG" ] || return 0
  local size; size=$(wc -c <"$LOG" 2>/dev/null || echo 0)
  [ "$size" -gt "$max" ] || return 0
  mv -f "$LOG" "${LOG}.$(date +%Y%m%d_%H%M%S)"
  ls -1t "${LOG}."* 2>/dev/null | tail -n +$(( ${LOG_RETENTION_DAYS:-7} + 1 )) | xargs -r rm -f
}
i(){ rot; echo "[INFO  $(ts)] $*" | tee -a "$LOG"; }
e(){ rot; echo "[ERROR $(ts)] $*" | tee -a "$LOG"; }

[ -f "$CONF" ] || { e "missing $CONF"; exit 1; }
# shellcheck source=/dev/null
. "$CONF"

# timeout shim (you had this idea, we keep it)
if ! command -v timeout >/dev/null 2>&1; then
  if command -v toybox >/dev/null 2>&1; then
    timeout(){ toybox timeout "$@"; }
  else
    timeout(){ "$@"; }
  fi
fi

export ADB_VENDOR_KEYS="${ADB_VENDOR_KEYS:-$HOME/.android}"

# same logic as your mdns_one, but NOT inside a subshell
mdns_one(){
  __tyrun mdns services 2>/dev/null \
    | awk '/_adb-tls-connect\._tcp/ {print $NF; exit}'
}

discover(){
  local ep=""
  # this now actually times out correctly and still uses your function
  ep=$(timeout "${MDNS_TIMEOUT:-25}" "$ADB_BIN" mdns services 2>/dev/null | awk '/_adb-tls-connect\._tcp/ {print $NF; exit}' || true)
  if [ -z "$ep" ]; then
    # fallback to last exact endpoint, not a rewritten :5555 transport
    if [ -f "$ST" ]; then
      local saved
      saved=$(cat "$ST")
      [ -n "$saved" ] && { echo "$saved"; return 0; }
    fi
    return 1
  fi
  echo "$ep"
}

connect(){
  local ep="$1"

  [ "${KILL_SERVER_ON_START:-no}" = "yes" ] && {
    i "kill-server"
    __tyrun kill-server || true
    sleep 1
  }

  i "connect $ep"
  printf '%s\n' "$ep" > "$TYADB_LAST_HOST_FILE"

  if timeout "${CONNECT_TIMEOUT:-20}" "$ADB_BIN" connect "$ep" 2>&1 | grep -Eq 'connected|already connected'; then
    printf '%s\n' "$ep" > "$ST"
    printf '%s\n' "$ep" > "$LEGACY_ST"
    return 0
  fi

  e "connect fail $ep"
  return 1
}

ok(){
  __tyrun -s "$1" get-state 2>/dev/null | grep -qx device
}

main(){
  # singleton check
  exec 9>"$PID.lock"
  if ! flock -n 9; then
    i "daemon already running (lock held), exiting"
    exit 0
  fi

  echo $$ > "$PID"
  i "daemon start"
  local back="${MIN_BACKOFF:-5}"
  local tries=0

  while true; do
    local ep=""
    if [ "${USE_MDNS:-yes}" = "yes" ] && ep=$(discover); then
      if connect "$ep"; then
        back="${MIN_BACKOFF:-5}"
        tries=0
        local s
        s=$(cat "$ST")
        i "monitor $s"
        while ok "$s"; do
          sleep "${HEALTH_CHECK_INTERVAL:-45}"
        done
        i "lost $s"
      fi
    else
      i "no device"
    fi
    tries=$((tries+1))
    if [ "${MAX_RETRIES:-15}" -gt 0 ] && [ "$tries" -ge "${MAX_RETRIES:-15}" ]; then
      e "max retries"
      exit 1
    fi
    i "retry $tries sleep ${back}s"
    sleep "$back"
    back=$(( back * 2 ))
    [ "$back" -gt "${MAX_BACKOFF:-90}" ] && back="${MAX_BACKOFF:-90}"
  done
}

trap 'i "stop"; exit 0' TERM INT
main
