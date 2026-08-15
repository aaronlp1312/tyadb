#!/data/data/com.termux/files/usr/bin/python
import base64, json, os, re, shlex, subprocess, threading, time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

# ---- Session & Cache
DELIM = "___TYADB_EOF___"
LOCK = threading.RLock()
SESS = {}  # key -> {"p": Popen, "lock": threading.RLock(), "ts": last_used}
PKG_CACHE = {} # serial -> {"data": [], "ts": timestamp}
COMMON_INTENTS = [
    {
        "id": "settings",
        "title": "Android Settings",
        "action": "android.settings.SETTINGS",
        "category": "settings",
        "command": "am start -a android.settings.SETTINGS"
    },
    {
        "id": "wireless_debugging",
        "title": "Wireless Debugging",
        "action": "android.settings.APPLICATION_DEVELOPMENT_SETTINGS",
        "category": "developer",
        "command": "am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS"
    },
    {
        "id": "app_settings",
        "title": "App Details",
        "action": "android.settings.APPLICATION_DETAILS_SETTINGS",
        "category": "package",
        "command": "am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:{package}"
    },
    {
        "id": "notification_settings",
        "title": "Notification Settings",
        "action": "android.settings.APP_NOTIFICATION_SETTINGS",
        "category": "package",
        "command": "am start -a android.settings.APP_NOTIFICATION_SETTINGS --es android.provider.extra.APP_PACKAGE {package}"
    },
    {
        "id": "accessibility",
        "title": "Accessibility Settings",
        "action": "android.settings.ACCESSIBILITY_SETTINGS",
        "category": "settings",
        "command": "am start -a android.settings.ACCESSIBILITY_SETTINGS"
    },
    {
        "id": "manage_overlay",
        "title": "Draw Over Other Apps",
        "action": "android.settings.action.MANAGE_OVERLAY_PERMISSION",
        "category": "package",
        "command": "am start -a android.settings.action.MANAGE_OVERLAY_PERMISSION -d package:{package}"
    },
]

def _now(): return time.time()

def _adb_cmd(key, args, timeout=30):
    cmd = ["adb"]
    if key:
        cmd += ["-s", key]
    cmd += list(args)
    try:
        res = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            errors="ignore",
            timeout=timeout
        )
        return res.returncode, (res.stdout or "") + (res.stderr or "")
    except FileNotFoundError:
        return 127, "[tyadb] adb not found in PATH"
    except subprocess.TimeoutExpired:
        return 124, "[tyadb] command timeout"

def _connected_devices():
    code, out = _adb_cmd("", ["devices", "-l"], timeout=10)
    devices = []
    for line in out.splitlines()[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        serial, state = parts[0], parts[1]
        meta = {}
        for item in parts[2:]:
            if ":" in item:
                k, v = item.split(":", 1)
                meta[k] = v
        devices.append({"serial": serial, "state": state, "meta": meta})
    return {"exit": code, "devices": devices, "raw": out}

def _resolve_serial(serial):
    if serial:
        return serial, None
    devices = [d for d in _connected_devices()["devices"] if d["state"] == "device"]
    if len(devices) == 1:
        return devices[0]["serial"], None
    if len(devices) > 1:
        return "", "multiple devices connected; pass serial"
    return "", "no connected device"

def _shell_once(serial, command, timeout=30):
    key, warning = _resolve_serial(serial)
    if warning and not key:
        return 2, f"[tyadb] {warning}"
    return _adb_cmd(key, ["shell", command], timeout=timeout)

# ---- ADB Shell Management
def _start_shell(key):
    with LOCK:
        if key in SESS and SESS[key]["p"].poll() is None:
            return SESS[key]
        cmd = ["adb"]
        if key: cmd += ["-s", key]
        cmd += ["shell", "-t"]
        p = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, bufsize=1
        )
        SESS[key] = {"p": p, "lock": threading.RLock(), "ts": _now()}
        return SESS[key]

def _stop_shell(key):
    with LOCK:
        s = SESS.get(key)
        if not s: return False
        try:
            if s["p"].poll() is None:
                try:
                    s["p"].stdin.write("exit\n")
                    s["p"].stdin.flush()
                except: pass
                s["p"].terminate()
        finally:
            try: s["p"].kill()
            except: pass
            if key in SESS: del SESS[key]
        return True

def _exec_in_shell(key, command, timeout=30):
    s = _start_shell(key)
    marker = f"{DELIM}:{time.time_ns()}"
    wrapped = f"{command}\necho {marker}:$?\n"
    out = []
    code = 127
    with s["lock"]:
        s["ts"] = _now()
        try:
            s["p"].stdin.write(wrapped)
            s["p"].stdin.flush()
        except Exception as e:
            return 127, f"[tyadb] failed to write: {e}"
        start = _now()
        while True:
            if (_now() - start) > timeout: return 124, "[tyadb] timeout"
            line = s["p"].stdout.readline()
            if not line: return 127, "[tyadb] shell died"
            line = line.rstrip("\r\n")
            if line.startswith(marker + ":"):
                try: code = int(line.split(":",2)[-1])
                except: code = 1
                break
            out.append(line)
    return code, "\n".join(out)

# ---- Package Management logic (ported from legacy scripts)
def _parse_dumpsys(text):
    blocks = re.split(r"\n\s*Package \[", text)[1:]
    apps = []
    for block in blocks:
        if "]" not in block: continue
        pkg_name = block.split("]", 1)[0].strip()
        info = {
            "package": pkg_name, 
            "version": {}, 
            "installer": None, 
            "path": None, 
            "group": "USER", 
            "tier": "safe",
            "label": None,
            "status": "enabled"
        }
        
        # label guessing (ported from tydebloat_plus2.sh)
        lbl_match = re.search(r"nonLocalizedLabel=(.*)", block)
        if lbl_match:
            val = lbl_match.group(1).strip()
            if val != "null": info["label"] = val
        
        if not info["label"]:
            # Pretty name from package suffix
            parts = pkg_name.split(".")
            suffix = parts[-1] if len(parts) > 1 else pkg_name
            info["label"] = suffix.replace("_", " ").title()

        # status check
        if "enabled=1" in block or "enabled=true" in block:
            info["status"] = "enabled"
        elif "enabled=2" in block or "enabled=false" in block or "disabled=true" in block:
            info["status"] = "disabled"

        # version & path
        vname = re.search(r"versionName=(.*)", block)
        vcode = re.search(r"versionCode=(.*)", block)
        path = re.search(r"codePath=(.*)", block)
        inst = re.search(r"installerPackageName=(.*)", block)
        flags = re.search(r"flags=\[(.*)\]", block)
        
        if vname: info["version"]["name"] = vname.group(1).strip()
        if vcode: info["version"]["code"] = vcode.group(1).split()[0]
        if path: info["path"] = path.group(1).strip()
        if inst:
            val = inst.group(1).strip()
            info["installer"] = None if val == "null" else val
        
        # Classification Heuristics
        f_str = flags.group(1) if flags else ""
        p = info["path"] or ""
        i = info["installer"] or ""
        
        is_priv = "/priv-app/" in p or "CORE" in f_str
        is_sys = any(x in p for x in ["/system/", "/product/", "/vendor/", "/system_ext/"]) or "SYSTEM" in f_str
        
        if is_priv: info["group"], info["tier"] = "PRIV", "unsafe"
        elif is_sys: info["group"], info["tier"] = "SYSTEM", "advanced"
        else:
            if i and re.search(r"(vending|google.android.packageinstaller|samsungapps|galaxyapps|com\.amazon\.venezia)", i):
                info["group"] = "USER" if "/data/app/" in p else "PRELOAD"
                info["tier"] = "safe"
            else:
                info["group"] = "PRELOAD"
                info["tier"] = "safe"
        apps.append(info)
    return apps

def _get_packages(key, force=False):
    now = _now()
    if not force and key in PKG_CACHE and (now - PKG_CACHE[key]["ts"]) < 300:
        return PKG_CACHE[key]["data"]
    
    # Run heavy dumpsys
    # We use subprocess.run for the big dump to avoid polluting the interactive shell
    cmd = ["adb"]
    if key: cmd += ["-s", key]
    cmd += ["shell", "dumpsys package packages"]
    res = subprocess.run(cmd, capture_output=True, text=True, errors="ignore")
    if res.returncode != 0: return []
    
    apps = _parse_dumpsys(res.stdout)
    PKG_CACHE[key] = {"data": apps, "ts": now}
    return apps

def _device_summary(serial=""):
    key, warning = _resolve_serial(serial)
    devices = _connected_devices()
    if not key:
        return {"serial": "", "warning": warning, "devices": devices["devices"]}

    props = {}
    for name in [
        "ro.product.model",
        "ro.product.manufacturer",
        "ro.build.version.release",
        "ro.build.version.sdk",
        "ro.build.fingerprint",
    ]:
        code, out = _adb_cmd(key, ["shell", "getprop", name], timeout=8)
        props[name] = out.strip() if code == 0 else ""

    code, battery = _adb_cmd(key, ["shell", "dumpsys", "battery"], timeout=8)
    level = None
    for line in battery.splitlines():
        if "level:" in line:
            level = line.split(":", 1)[1].strip()
            break

    return {
        "serial": key,
        "state": "device",
        "devices": devices["devices"],
        "model": props.get("ro.product.model", ""),
        "manufacturer": props.get("ro.product.manufacturer", ""),
        "android": props.get("ro.build.version.release", ""),
        "sdk": props.get("ro.build.version.sdk", ""),
        "fingerprint": props.get("ro.build.fingerprint", ""),
        "battery": level,
        "warning": warning,
    }

def _settings_list(serial, namespace):
    if namespace not in {"system", "secure", "global"}:
        return 2, f"invalid settings namespace: {namespace}", []
    code, out = _shell_once(serial, f"settings list {namespace}", timeout=20)
    rows = []
    if code == 0:
        for line in out.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                rows.append({"key": key, "value": value})
    return code, out, rows

def _settings_put(serial, namespace, key, value):
    if namespace not in {"system", "secure", "global"}:
        return 2, f"invalid settings namespace: {namespace}"
    if not re.match(r"^[A-Za-z0-9_.:-]+$", key or ""):
        return 2, "invalid settings key"
    cmd = "settings put {} {} {}".format(
        shlex.quote(namespace),
        shlex.quote(key),
        shlex.quote(str(value))
    )
    return _shell_once(serial, cmd, timeout=20)

def _package_action(serial, package, action):
    if not re.match(r"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$", package or ""):
        return 2, "invalid package name"
    qpkg = shlex.quote(package)
    commands = {
        "force_stop": f"am force-stop {qpkg}",
        "clear": f"pm clear {qpkg}",
        "disable": f"pm disable-user --user 0 {qpkg}",
        "enable": f"pm enable {qpkg}",
        "uninstall_user0": f"pm uninstall --user 0 {qpkg}",
    }
    if action not in commands:
        return 2, f"invalid package action: {action}"
    return _shell_once(serial, commands[action], timeout=45)

def _intent_command(req):
    action = str(req.get("action", "") or "")
    component = str(req.get("component", "") or "")
    data = str(req.get("data", "") or "")
    package = str(req.get("package", "") or "")
    categories = req.get("categories", []) or []
    extras = req.get("extras", {}) or {}

    if not action and not component:
        return None, "intent launch requires action or component"

    cmd = ["am", "start"]
    if action:
        cmd += ["-a", action]
    for category in categories:
        cmd += ["-c", str(category)]
    if data:
        cmd += ["-d", data]
    if package:
        cmd += ["-p", package]
    if component:
        cmd += ["-n", component]
    for key, value in extras.items():
        cmd += ["--es", str(key), str(value)]
    return " ".join(shlex.quote(x) for x in cmd), None

def _discover_package_activities(serial, package):
    if not package:
        return []
    code, out = _shell_once(serial, f"cmd package resolve-activity --brief {shlex.quote(package)}", timeout=10)
    activities = []
    if code == 0:
        for line in out.splitlines():
            line = line.strip()
            if "/" in line and not line.startswith("priority="):
                activities.append({"component": line, "kind": "resolved-main"})
    code, out = _shell_once(serial, f"cmd package dump {shlex.quote(package)}", timeout=20)
    if code == 0:
        for line in out.splitlines():
            text = line.strip()
            if re.match(r"^[A-Fa-f0-9]+ .+/.* filter ", text):
                comp = text.split()[1]
                if "/" in comp and not any(a["component"] == comp for a in activities):
                    activities.append({"component": comp, "kind": "declared"})
    return activities[:200]

# ---- HTTP API
class H(BaseHTTPRequestHandler):
    def _ok(self, body=b"ok", ct="text/plain"):
        self.send_response(200)
        self.send_header("Content-Type", ct)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj): self._ok(json.dumps(obj).encode(), "application/json")

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def _notfound(self):
        self.send_response(404)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(b"not found")

    def do_GET(self):
        p = urlparse(self.path)
        if p.path == "/":
            self._json({
                "ok": True,
                "name": "tyadb-python-bridge",
                "mode": "broker-prototype",
                "endpoints": [
                    "/health", "/sessions", "/devices", "/open", "/exec", "/close",
                    "/broker/capabilities", "/broker/device", "/broker/packages",
                    "/broker/intents", "/broker/settings"
                ]
            })
        elif p.path == "/health": self._ok(b"ok")
        elif p.path == "/sessions":
            with LOCK:
                payload = {"sessions":[{"key":k, "alive": (v["p"].poll() is None), "last": v["ts"]} for k,v in SESS.items()]}
            self._json(payload)
        elif p.path == "/devices":
            self._json(_connected_devices())
        elif p.path == "/packages":
            qs = parse_qs(p.query)
            serial = qs.get("serial", [""])[0]
            force = "force" in qs
            self._json({"apps": _get_packages(serial, force)})
        elif p.path == "/broker/capabilities":
            self._json({
                "ok": True,
                "name": "TyDroid Broker Prototype",
                "backend": "stock-adb",
                "services": {
                    "terminal": ["exec", "open", "close"],
                    "device": ["summary", "devices"],
                    "packages": ["list", "force_stop", "clear", "disable", "enable", "uninstall_user0"],
                    "intents": ["catalog", "package_activities", "launch"],
                    "settings": ["list", "put"]
                },
                "limits": [
                    "uses stock adb backend",
                    "requires an authorized ADB device",
                    "typed endpoints are prototype policy surface, not final permission broker"
                ]
            })
        elif p.path == "/broker/device":
            qs = parse_qs(p.query)
            self._json(_device_summary(qs.get("serial", [""])[0]))
        elif p.path == "/broker/packages":
            qs = parse_qs(p.query)
            serial = qs.get("serial", [""])[0]
            force = "force" in qs
            apps = _get_packages(serial, force)
            self._json({"serial": serial, "count": len(apps), "apps": apps})
        elif p.path == "/broker/intents":
            qs = parse_qs(p.query)
            serial = qs.get("serial", [""])[0]
            package = qs.get("package", [""])[0]
            self._json({
                "catalog": COMMON_INTENTS,
                "package": package,
                "activities": _discover_package_activities(serial, package) if package else []
            })
        elif p.path == "/broker/settings":
            qs = parse_qs(p.query)
            namespace = qs.get("namespace", ["global"])[0]
            serial = qs.get("serial", [""])[0]
            code, out, rows = _settings_list(serial, namespace)
            self._json({"exit": code, "namespace": namespace, "settings": rows, "raw_b64": base64.b64encode(out.encode()).decode()})
        else: self._notfound()

    def do_POST(self):
        ln = int(self.headers.get("Content-Length","0") or 0)
        req = json.loads(self.rfile.read(ln).decode() or "{}") if ln else {}
        p = urlparse(self.path)
        serial = str(req.get("serial","") or "")

        if p.path == "/exec" or p.path == "/broker/terminal":
            cmd, to = str(req.get("cmd","")), int(req.get("timeout",30))
            code, out = _exec_in_shell(serial, cmd, timeout=to)
            self._json({"exit":code, "out_b64": base64.b64encode(out.encode()).decode()})
        elif p.path == "/command" or p.path == "/sendCommand":
            cmd, to = str(req.get("cmd", req.get("command",""))), int(req.get("timeout",30))
            code, out = _exec_in_shell(serial, cmd, timeout=to)
            encoded = base64.b64encode(out.encode()).decode()
            self._json({"exit":code, "out_b64": encoded, "result": encoded, "command": cmd, "path": "~", "home": os.path.expanduser("~")})
        elif p.path == "/open":
            _start_shell(serial)
            self._json({"ok":True, "serial":serial})
        elif p.path == "/close":
            self._json({"ok": _stop_shell(serial), "serial": serial})
        elif p.path == "/broker/package/action":
            code, out = _package_action(serial, str(req.get("package", "") or ""), str(req.get("action", "") or ""))
            self._json({"exit": code, "out_b64": base64.b64encode(out.encode()).decode()})
        elif p.path == "/broker/intent/launch":
            cmd, err = _intent_command(req)
            if err:
                self._json({"exit": 2, "out_b64": base64.b64encode(err.encode()).decode()})
            else:
                code, out = _shell_once(serial, cmd, timeout=20)
                self._json({"exit": code, "command": cmd, "out_b64": base64.b64encode(out.encode()).decode()})
        elif p.path == "/broker/settings":
            code, out = _settings_put(serial, str(req.get("namespace", "") or ""), str(req.get("key", "") or ""), str(req.get("value", "") or ""))
            self._json({"exit": code, "out_b64": base64.b64encode(out.encode()).decode()})
        else: self._notfound()

def main():
    srv = None
    port = None
    for p in [1312] + list(range(1313, 1321)):
        try:
            srv = HTTPServer(("127.0.0.1", p), H)
            port = p; break
        except OSError: continue
    if srv is None:
        print("[tyadb] no free port 1312..1320")
        return
    print(f"[tyadb] listening on http://127.0.0.1:{port}")
    try: srv.serve_forever()
    except KeyboardInterrupt: pass

if __name__ == "__main__": main()
