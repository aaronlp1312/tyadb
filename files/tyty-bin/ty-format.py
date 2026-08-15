#!/usr/bin/env python3
import json, sys, re
data = sys.stdin.read()
lines = data.splitlines()
devices = []
for line in lines[1:]:
  s = line.strip()
  if not s or not s.endswith("device"): continue
  parts = s.split()
  serial = parts[0]
  info = " ".join(parts[1:])
  model = m = re.search(r'model:(\S+)', info)
  devices.append({"serial": serial, "model": (m.group(1) if m else "")})
print(json.dumps({"count": len(devices), "devices": devices}))
