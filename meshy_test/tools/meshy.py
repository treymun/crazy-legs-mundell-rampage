"""Tiny Meshy API client with a hard credit cap.

The API key is never read here: the session's network proxy injects it into
requests to api.meshy.ai. The Authorization header below is a placeholder that
the proxy overwrites.

  meshy.py balance
  meshy.py submit <endpoint> <body.json> <max_cost> <label>   -> prints task id
  meshy.py wait <endpoint> <task_id> <label>                  -> waits, logs cost, downloads
"""

import base64
import json
import os
import sys
import time
import urllib.request

API = "https://api.meshy.ai/openapi/"
HEAD = {"Authorization": "Bearer proxy-injected", "Content-Type": "application/json"}
HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "ledger.json")
START = 3100  # balance before the test began
LIMIT = 250  # the owner's cap for this test


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method, headers=HEAD)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read()[:800].decode(errors='replace')}")


def balance():
    return call("GET", "v1/balance")["balance"]


def ledger():
    if os.path.exists(LEDGER):
        return json.load(open(LEDGER))
    return {"start": START, "limit": LIMIT, "entries": []}


def save(led):
    json.dump(led, open(LEDGER, "w"), indent=1)


def data_uri(path):
    mime = "image/png" if path.endswith(".png") else "image/jpeg"
    return f"data:{mime};base64," + base64.b64encode(open(path, "rb").read()).decode()


def expand(body):
    """Replace "@file:<path>" strings with data URIs."""
    if isinstance(body, dict):
        return {k: expand(v) for k, v in body.items()}
    if isinstance(body, list):
        return [expand(v) for v in body]
    if isinstance(body, str) and body.startswith("@file:"):
        return data_uri(os.path.join(HERE, body[6:]))
    return body


def submit(endpoint, body_path, max_cost, label):
    led = ledger()
    pending = [e for e in led["entries"] if e.get("cost") is None]
    if pending:
        sys.exit(f"refused: {len(pending)} task(s) still unsettled; wait for them first")
    bal = balance()
    spent = START - bal
    if spent + max_cost > LIMIT:
        sys.exit(f"refused: spent {spent}, this may cost {max_cost}, cap {LIMIT}")
    body = expand(json.load(open(os.path.join(HERE, body_path))))
    res = call("POST", endpoint, body)
    tid = res["result"]
    led["entries"].append(
        {"label": label, "endpoint": endpoint, "task": tid, "before": bal, "cost": None,
         "body": body_path, "time": time.strftime("%H:%M:%S")}
    )
    save(led)
    print(tid)


def wait(endpoint, tid, label):
    while True:
        t = call("GET", f"{endpoint}/{tid}")
        st = t.get("status")
        print(st, t.get("progress"), flush=True)
        if st in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
            break
        time.sleep(10)
    out = os.path.join(HERE, "out", label)
    os.makedirs(out, exist_ok=True)
    json.dump(t, open(os.path.join(out, "task.json"), "w"), indent=1)
    time.sleep(3)
    bal = balance()
    led = ledger()
    for e in led["entries"]:
        if e["task"] == tid:
            e["cost"] = e["before"] - bal
            e["status"] = st
            print("cost", e["cost"], "balance", bal, "total spent", START - bal)
    save(led)
    if st != "SUCCEEDED":
        print(json.dumps(t.get("task_error")))
        return
    urls = {}
    for k, v in (t.get("model_urls") or {}).items():
        if v and k in ("glb",):
            urls[f"model.{k}"] = v
    for i, u in enumerate(t.get("image_urls") or []):
        urls[f"image_{i}.png"] = u
    for i, tex in enumerate(t.get("texture_urls") or []):
        for k, v in tex.items():
            if v:
                urls[f"tex{i}_{k}.png"] = v
    if t.get("thumbnail_url"):
        urls["thumb.png"] = t["thumbnail_url"]
    for name, u in urls.items():
        urllib.request.urlretrieve(u, os.path.join(out, name))
        print("got", name)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "balance":
        b = balance()
        print("balance", b, "spent in test", START - b)
    elif cmd == "submit":
        submit(sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5])
    elif cmd == "wait":
        wait(sys.argv[2], sys.argv[3], sys.argv[4])
