#!/usr/bin/env python3
"""Fetch every TDX path of one list into out/<name>.json.gz.

Run by .github/workflows/tdx-batch.yml with the owner's key in the
environment (TDX_CLIENT_ID, TDX_CLIENT_SECRET); never prints the key or the
token. A list line is `<name><TAB><path>`; `#` starts a comment. A failed
path is recorded in out/manifest.json and the batch goes on.

    python3 -I tools/tdx-batch/fetch.py tools/tdx-batch/lists/bus.txt out
"""
import datetime, gzip, json, os, re, sys, time, urllib.error, urllib.parse, urllib.request

TOKEN_URL = "https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token"
PATH_RE = re.compile(r"/api/(basic|advanced|historical)/[A-Za-z0-9/_.\-]+(\?[^#\x00-\x1f\x7f]*)?")
NAME_RE = re.compile(r"[A-Za-z0-9_.\-]+")


def token():
    payload = urllib.parse.urlencode({
        "grant_type": "client_credentials",
        "client_id": os.environ["TDX_CLIENT_ID"],
        "client_secret": os.environ["TDX_CLIENT_SECRET"],
    }).encode()
    request = urllib.request.Request(TOKEN_URL, data=payload,
                                     headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(request, timeout=60) as response:
        value = json.loads(response.read()).get("access_token")
    if not value:
        sys.exit("The token request answered without an access_token")
    return value


def read_list(path):
    entries = []
    for line in open(path, encoding="utf-8"):
        line = line.split("#", 1)[0].rstrip("\n") if not line.lstrip().startswith("#") else ""
        if not line.strip():
            continue
        name, _, api = line.partition("\t")
        name, api = name.strip(), api.strip()
        if not NAME_RE.fullmatch(name) or not PATH_RE.fullmatch(api) or ".." in api.split("?")[0].split("/"):
            sys.exit(f"Bad list line: {line!r}")
        entries.append((name, api))
    return entries


def count(body):
    try:
        data = json.loads(body)
    except ValueError:
        return None
    if isinstance(data, list):
        return len(data)
    if isinstance(data, dict):
        lists = [len(v) for v in data.values() if isinstance(v, list)]
        return max(lists) if lists else 1
    return 1


def main():
    list_path, out = sys.argv[1], sys.argv[2]
    if not os.environ.get("TDX_CLIENT_ID") or not os.environ.get("TDX_CLIENT_SECRET"):
        sys.exit("TDX_CLIENT_ID / TDX_CLIENT_SECRET are not set for this run")
    os.makedirs(out, exist_ok=True)
    entries = read_list(list_path)
    bearer, got_at = token(), time.time()
    print("Token: received")
    manifest = []
    for name, api in entries:
        if time.time() - got_at > 3600:
            bearer, got_at = token(), time.time()
        path, _, query = api.partition("?")
        url = "https://tdx.transportdata.tw" + path + ("?" + urllib.parse.quote(query, safe="$&=,:'()%+-_./") if query else "")
        request = urllib.request.Request(url, headers={"Accept-Encoding": "identity"})
        request.add_unredirected_header("Authorization", "Bearer " + bearer)
        row = {"name": name, "path": api,
               "fetched_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
        for attempt in range(3):
            try:
                with urllib.request.urlopen(request, timeout=300) as response:
                    body = response.read()
                with gzip.open(os.path.join(out, name + ".json.gz"), "wb", compresslevel=9) as file:
                    file.write(body)
                row.update(status=200, bytes=len(body), records=count(body))
                break
            except urllib.error.HTTPError as error:
                row.update(status=error.code, error=error.read()[:300].decode("utf-8", "replace"))
                if error.code != 429 and error.code < 500:
                    break
            except (urllib.error.URLError, TimeoutError) as error:
                row.update(status=0, error=str(getattr(error, "reason", error))[:300])
            time.sleep(10 * (attempt + 1))
        print(f"{name}: {row['status']} {row.get('bytes', 0):,} bytes {row.get('records')} records")
        manifest.append(row)
        time.sleep(1)
    with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as file:
        json.dump(manifest, file, ensure_ascii=False, indent=1)
    ok = sum(1 for row in manifest if row["status"] == 200)
    print(f"{ok} of {len(manifest)} paths answered; {sum(r.get('bytes', 0) for r in manifest):,} bytes in all")


if __name__ == "__main__":
    main()
