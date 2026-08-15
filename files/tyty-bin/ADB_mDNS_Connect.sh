#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
mdns_ep="$(adb mdns services 2>/dev/null | awk '/_adb-tls-connect\._tcp/ {print $NF}' | head -n1 || true)"
if [ -z "$mdns_ep" ]; then termux-toast -g top "No _adb-tls-connect service found"; exit 1; fi
host="${mdns_ep%:*}"; port="${mdns_ep##*:}"

adb kill-server || true
if adb connect "$mdns_ep"; then
  if [ "$port" != "5555" ]; then adb -s "$mdns_ep" tcpip 5555 || true; sleep 1; fi
  if adb connect "${host}:5555"; then
    termux-toast -g top "Connected ${host}:5555"
  else
    termux-toast -g top "Reconnect to ${host}:5555 failed"
  fi
else
  termux-toast -g top "Connect to $mdns_ep failed"
fi
