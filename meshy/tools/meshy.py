"""Meshy API client for the Meshy models track, with a hard credit cap.

The key is read at call time from ~/.clmr/meshy_key.txt and is never printed,
logged, stored or passed anywhere but the Authorization header of a request
to api.meshy.ai. Every paid call is recorded in meshy/credit_ledger.json with
the balance read before and after it.

  meshy.py balance
  meshy.py submit <endpoint> <body.json> <max_cost> <label>   -> prints task id
  meshy.py wait <endpoint> <task_id> <label> <out_dir>        -> waits, logs cost, downloads
  meshy.py run <endpoint> <body.json> <max_cost> <label> <out_dir>   (submit + wait)

A body may use "@file:<path>" (a data URI of that image) and
"@task:<label>" (the task id recorded for that label).
"""

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.meshy.ai/openapi/"
HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(os.path.dirname(HERE), "credit_ledger.json")
KEY_FILE = os.path.join(os.path.expanduser("~"), ".clmr", "meshy_key.txt")
START = 2938  # balance when this track began (2026-11-25)
LIMIT = 2500  # the owner's hard cap for this track


def _head():
    with open(KEY_FILE, encoding="utf-8") as f:
        key = f.read().strip()
    return {"Authorization": "Bearer " + key, "Content-Type": "application/json"}


def call(method, path, body=None, tries=4):
    data = json.dumps(body).encode() if body is not None else None
    for attempt in range(tries):
        req = urllib.request.Request(API + path, data=data, method=method, headers=_head())
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.loads(r.read() or b"null")
        except urllib.error.HTTPError as e:
            msg = e.read()[:800].decode(errors="replace")
            if e.code >= 500 and attempt < tries - 1 and method == "GET":
                time.sleep(5)
                continue
            sys.exit(f"HTTP {e.code}: {msg}")
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < tries - 1 and method == "GET":
                time.sleep(5)
                continue
            sys.exit(f"network: {e}")


def balance():
    return call("GET", "v1/balance")["balance"]


def ledger():
    if os.path.exists(LEDGER):
        with open(LEDGER, encoding="utf-8") as f:
            return json.load(f)
    return {"start": START, "limit": LIMIT, "entries": []}


def save(led):
    with open(LEDGER, "w", encoding="utf-8") as f:
        json.dump(led, f, indent=1)


def data_uri(path):
    mime = "image/png" if path.lower().endswith(".png") else "image/jpeg"
    with open(path, "rb") as f:
        return f"data:{mime};base64," + base64.b64encode(f.read()).decode()


def expand(body, led):
    if isinstance(body, dict):
        return {k: expand(v, led) for k, v in body.items()}
    if isinstance(body, list):
        return [expand(v, led) for v in body]
    if isinstance(body, str) and body.startswith("@file:"):
        return data_uri(body[6:])
    if isinstance(body, str) and body.startswith("@task:"):
        want = body[6:]
        for e in reversed(led["entries"]):
            if e["label"] == want and e.get("status") == "SUCCEEDED":
                return e["task"]
        sys.exit(f"no succeeded task labelled {want}")
    return body


def spent_now(bal):
    return START - bal


def submit(endpoint, body_path, max_cost, label):
    led = ledger()
    pending = [e for e in led["entries"] if e.get("cost") is None]
    if pending:
        sys.exit(f"refused: {len(pending)} task(s) still unsettled; wait for them first")
    bal = balance()
    spent = spent_now(bal)
    if spent + max_cost > LIMIT:
        sys.exit(f"refused: spent {spent}, this may cost {max_cost}, cap {LIMIT}")
    with open(body_path, encoding="utf-8") as f:
        body = expand(json.load(f), led)
    res = call("POST", endpoint, body)
    tid = res["result"]
    led["entries"].append(
        {"label": label, "endpoint": endpoint, "task": tid, "before": bal, "cost": None,
         "body": os.path.basename(body_path), "time": time.strftime("%Y-%m-%d %H:%M:%S")}
    )
    save(led)
    print(tid)
    return tid


def wait(endpoint, tid, label, out):
    last = None
    while True:
        t = call("GET", f"{endpoint}/{tid}")
        st = t.get("status")
        if (st, t.get("progress")) != last:
            print(st, t.get("progress"), flush=True)
            last = (st, t.get("progress"))
        if st in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
            break
        time.sleep(8)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "task.json"), "w", encoding="utf-8") as f:
        json.dump(t, f, indent=1)
    time.sleep(4)
    bal = balance()
    led = ledger()
    for e in led["entries"]:
        if e["task"] == tid:
            e["cost"] = e["before"] - bal
            e["after"] = bal
            e["status"] = st
            print("cost", e["cost"], "balance", bal, "track spent", spent_now(bal))
    save(led)
    if st != "SUCCEEDED":
        print("FAILED", json.dumps(t.get("task_error")))
        return False
    urls = {}
    for k, v in (t.get("model_urls") or {}).items():
        if v and k in ("glb", "fbx"):
            urls[f"model.{k}"] = v
    res = t.get("result") or {}
    for k, v in (res.get("rigged_character_glb_url") and {"rigged.glb": res["rigged_character_glb_url"]} or {}).items():
        urls[k] = v
    for anim, v in (res.get("basic_animations") or {}).items():
        if isinstance(v, str) and v.endswith(".glb") or (isinstance(v, str) and "glb" in anim):
            urls[f"anim_{anim}.glb"] = v
    for i, u in enumerate(t.get("image_urls") or []):
        urls[f"image_{i}.png"] = u
    for i, tex in enumerate(t.get("texture_urls") or []):
        for k, v in tex.items():
            if v:
                urls[f"tex{i}_{k}.png"] = v
    if t.get("thumbnail_url"):
        urls["thumb.png"] = t["thumbnail_url"]
    for name, u in urls.items():
        for attempt in range(3):
            try:
                urllib.request.urlretrieve(u, os.path.join(out, name))
                break
            except Exception as err:  # noqa: BLE001 - retry downloads
                if attempt == 2:
                    print("download failed", name, err)
                time.sleep(4)
        print("got", name)
    return True


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "balance":
        b = balance()
        print("balance", b, "track spent", spent_now(b), "cap", LIMIT)
    elif cmd == "submit":
        submit(sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5])
    elif cmd == "wait":
        ok = wait(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
        sys.exit(0 if ok else 2)
    elif cmd == "run":
        tid = submit(sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5])
        ok = wait(sys.argv[2], tid, sys.argv[5], sys.argv[6])
        sys.exit(0 if ok else 2)
