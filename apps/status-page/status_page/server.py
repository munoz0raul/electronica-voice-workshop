# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Qualcomm Innovation Center, Inc. All rights reserved.
"""Minimal fleet status page for the VENTUNO Q.

Polls the update-server and shows each device's current Target and version, so
a workshop audience sees a new model land after an OTA rollout. It is a cut-down
reimplementation of the demo dashboard's update-server client: the same API
calls (/v1/devices, /v1/updates, /v1/updates/<name>/tuf) and the same Bearer
token, read from /run/secrets.

The update-server API needs a token. Provide one of, in order:
  - env STATUS_TOKEN
  - /run/secrets/status-token
  - /run/secrets/dashboard-token   (reuse the demo dashboard's, if present)
When no token resolves, or the server refuses it, the page says so instead of
showing a stale or empty table.
"""

import json
import os
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPDATE_SERVER = os.environ.get("UPDATE_SERVER", "http://localhost:8080").rstrip("/")
PORT = int(os.environ.get("PORT", "8081"))
POLL_S = int(os.environ.get("POLL_S", "5"))
SECRETS_DIR = os.environ.get("SECRETS_DIR", "/run/secrets")
# A device seen within this many seconds counts as online (the update-server
# records a check-in at most once a minute; matches the dashboard's window).
OFFLINE_AFTER_S = 150


def log(msg):
    print(f"status-page: {msg}", flush=True)


def read_token():
    tok = os.environ.get("STATUS_TOKEN")
    if tok:
        return tok.strip()
    for name in ("status-token", "dashboard-token"):
        try:
            with open(os.path.join(SECRETS_DIR, name)) as f:
                v = f.read().strip()
                if v:
                    return v
        except OSError:
            continue
    return None


def api_json(path, token, timeout=10):
    req = urllib.request.Request(UPDATE_SERVER + path,
                                 headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
    return json.loads(raw) if raw.strip() else None


def target_versions(token):
    """{target name: version} across every uploaded update's TUF metadata."""
    out = {}
    updates = api_json("/v1/updates", token) or []
    for u in updates:
        name = u.get("name")
        if not name:
            continue
        try:
            tuf = api_json(f"/v1/updates/{name}/tuf", token)
        except urllib.error.HTTPError:
            continue
        signed = (tuf or {}).get("targets.json", {}).get("signed", {})
        for tname, t in signed.get("targets", {}).items():
            custom = t.get("custom", {})
            out[tname] = custom.get("version")
    return out


def as_epoch(v):
    """last-seen as epoch seconds, or None. Accepts a number or ISO 8601 UTC."""
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str) and v:
        try:
            return time.mktime(time.strptime(v, "%Y-%m-%dT%H:%M:%SZ")) - time.timezone
        except ValueError:
            return None
    return None


class Poller(threading.Thread):
    daemon = True

    def __init__(self):
        super().__init__()
        self.lock = threading.Lock()
        self.state = {"ok": False, "error": "starting", "devices": [], "at": None}

    def snapshot(self):
        with self.lock:
            return dict(self.state)

    def run(self):
        while True:
            self._poll_once()
            time.sleep(POLL_S)

    def _poll_once(self):
        token = read_token()
        if not token:
            self._set(False, f"no token (set STATUS_TOKEN or put one in {SECRETS_DIR})", [])
            return
        try:
            devices = api_json("/v1/devices", token) or []
            versions = target_versions(token)
        except urllib.error.HTTPError as e:
            reason = "token refused (401/403)" if e.code in (401, 403) else f"HTTP {e.code}"
            self._set(False, f"{reason} from {UPDATE_SERVER}", [])
            return
        except (urllib.error.URLError, OSError) as e:
            self._set(False, f"cannot reach {UPDATE_SERVER}: {e}", [])
            return

        now = time.time()
        rows = []
        for d in devices:
            labels = d.get("labels", {})
            target = d.get("target")
            seen = as_epoch(d.get("last-seen"))
            rows.append({
                "name": labels.get("name", d.get("uuid", "?")),
                "group": labels.get("group") or "",
                "target": target or "",
                "version": versions.get(target) or "",
                "online": seen is not None and (now - seen) < OFFLINE_AFTER_S,
            })
        rows.sort(key=lambda r: r["name"])
        self._set(True, None, rows)

    def _set(self, ok, error, devices):
        with self.lock:
            self.state = {"ok": ok, "error": error, "devices": devices,
                          "at": time.strftime("%H:%M:%S")}
        if error:
            log(error)


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Fleet status</title>
<style>
  :root { color-scheme: dark; }
  body { font: 16px/1.4 system-ui, sans-serif; margin: 2rem; background:#0f1115; color:#e6e6e6; }
  h1 { font-size: 1.3rem; }
  table { border-collapse: collapse; width: 100%; max-width: 900px; margin-top: 1rem; }
  th, td { text-align: left; padding: .5rem .75rem; border-bottom: 1px solid #2a2e37; }
  th { color:#9aa4b2; font-weight:600; }
  .ver { font-weight:700; color:#7ee787; }
  .dot { display:inline-block; width:.6rem; height:.6rem; border-radius:50%; margin-right:.4rem; }
  .on { background:#2ea043; } .off { background:#6e7681; }
  .err { color:#ff7b72; margin-top:1rem; }
  .meta { color:#6e7681; font-size:.85rem; margin-top:1rem; }
</style>
</head>
<body>
<h1>UNO Q fleet &mdash; current target</h1>
<div id="root">loading&hellip;</div>
<script>
async function tick() {
  try {
    const r = await fetch('api', {cache: 'no-store'});
    const s = await r.json();
    const root = document.getElementById('root');
    let html = '';
    if (!s.ok) {
      html += '<div class="err">' + (s.error || 'no data') + '</div>';
    }
    if (s.devices && s.devices.length) {
      html += '<table><thead><tr><th>Device</th><th>Group</th><th>Target</th><th>Version</th></tr></thead><tbody>';
      for (const d of s.devices) {
        html += '<tr><td><span class="dot ' + (d.online?'on':'off') + '"></span>'
             +  d.name + '</td><td>' + d.group + '</td><td>' + d.target
             +  '</td><td class="ver">' + d.version + '</td></tr>';
      }
      html += '</tbody></table>';
    } else if (s.ok) {
      html += '<p>No devices registered yet.</p>';
    }
    html += '<div class="meta">update-server: ' + '%UPDATE_SERVER%'
         +  (s.at ? ' &middot; last poll ' + s.at : '') + '</div>';
    root.innerHTML = html;
  } catch (e) {
    document.getElementById('root').innerHTML =
      '<div class="err">status page cannot reach its own backend</div>';
  }
}
tick(); setInterval(tick, 3000);
</script>
</body>
</html>
""".replace("%UPDATE_SERVER%", UPDATE_SERVER)


class Handler(BaseHTTPRequestHandler):
    poller = None

    def log_message(self, *args):
        pass

    def _send(self, code, body, ctype):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.rstrip("/") in ("", "/index.html") or self.path == "/":
            self._send(200, PAGE, "text/html; charset=utf-8")
        elif self.path.rstrip("/") == "/api":
            self._send(200, json.dumps(self.poller.snapshot()), "application/json")
        else:
            self._send(404, "not found", "text/plain")


def main():
    poller = Poller()
    poller.start()
    Handler.poller = poller
    log(f"serving on :{PORT}, polling {UPDATE_SERVER} every {POLL_S}s")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
