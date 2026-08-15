#!/data/data/com.termux/files/usr/bin/sh
set -eu

# ===== CONFIG =====
DIR="$HOME/webterm"
LOG="$DIR/bridge.log"
PIDFILE="$DIR/bridge.pid"

PORTS="1312 15000 15001 15002 15003 15004"

termux-wake-lock >/dev/null 2>&1 || true

echo "[Bridge] starting $(date)" >> "$LOG"

cd "$DIR" || {
  echo "[Bridge] missing directory $DIR" | tee -a "$LOG"
  exit 1
}

# ===== already running? =====
if [ -f "$PIDFILE" ]; then
  PID="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
    echo "[Bridge] already running (pid $PID)" >> "$LOG"
    exit 0
  fi
fi

# ===== find python =====
PY="$(command -v python3 || command -v python || true)"

if [ -z "$PY" ]; then
  echo "[Bridge] python not found" | tee -a "$LOG"
  exit 1
fi

# ===== start server =====
for PORT in $PORTS; do
  echo "[Bridge] trying port $PORT" >> "$LOG"

  nohup "$PY" server.py --port "$PORT" >> "$LOG" 2>&1 &
  PID=$!

  sleep 1

  if ss -lnt 2>/dev/null | grep -q ":$PORT"; then
    echo "$PID" > "$PIDFILE"

    command -v termux-toast >/dev/null 2>&1 &&
      termux-toast "Tydroid Bridge Online :$PORT"

    echo "[Bridge] running on $PORT (pid $PID)" >> "$LOG"
    echo "Bridge online at http://127.0.0.1:$PORT"
    exit 0
  else
    echo "[Bridge] port $PORT failed" >> "$LOG"
    kill "$PID" 2>/dev/null || true
  fi
done

echo "[Bridge] FAILED — no ports bound" | tee -a "$LOG"
exit 1
