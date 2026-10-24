#!/usr/bin/env python3
"""Create the game's Game Center leaderboard and achievements in App Store Connect.

Reads docs/game-center/game-center.json (the same data docs/GAME_CENTER_SETUP.md
shows) and creates, through the App Store Connect API, whatever of it App
Store Connect does not have yet: the leaderboards with their localizations,
and the achievements with their localizations and images. Decision 396.

  game_center_setup.py [--apply] [--only all|leaderboards|achievements]
  game_center_setup.py --write-doc | --check-doc

Without --apply it is a dry run: it only reads App Store Connect and lists
what an apply would create; no request that writes is sent. With --apply it
prints the same full list first, then creates it. Either way it never
deletes or changes anything App Store Connect already has: an existing ID is
skipped (a difference from the table is reported, not fixed), so running it
again is safe and only adds what is still missing. An achievement whose image
is not in the repository yet is skipped whole.

--write-doc rewrites the generated tables in docs/GAME_CENTER_SETUP.md from
the JSON; --check-doc fails when they differ. Neither needs a key.

Inputs (environment), as in .github/workflows/game-center-setup.yml:
  ASC_APP_ID       variable: the app's Apple ID in App Store Connect
  ASC_KEY_ID       secret: the App Store Connect team API key ID
  ASC_ISSUER_ID    secret: the issuer ID
  ASC_PRIVATE_KEY  secret: the whole text of AuthKey_<key id>.p8
  GITHUB_STEP_SUMMARY  optional: the list is added to the job summary
  ASC_API_URL      tests only: the address of a fake App Store Connect

The ES256 token is made the way the TestFlight processing job makes it: this
uses its Client (.github/scripts/testflight-processing.py), standard library
and the openssl command only. Never prints the key, the key ID, the issuer
ID or a token. Tested with a fake App Store Connect by
test_game_center_setup.py.
"""

import argparse
import datetime
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "docs" / "game-center" / "game-center.json"
DOC = ROOT / "docs" / "GAME_CENTER_SETUP.md"
PROCESSING = ROOT / ".github" / "scripts" / "testflight-processing.py"
REQUIRED = ("ASC_APP_ID", "ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY")
POINTS_LIMIT = 1000
# Children (localizations, images) are added only to a version App Store
# Connect still lets the developer edit.
EDITABLE = "PREPARE_FOR_SUBMISSION"
LOCALE_NAMES = {"en-US": "English (U.S.)", "zh-Hant": "Chinese (Traditional)"}
DOC_BEGIN = "<!-- {name}: generated from docs/game-center/game-center.json by tools/game-center-setup/game_center_setup.py --write-doc; do not edit by hand -->"
DOC_END = "<!-- end {name} -->"

sys.dont_write_bytecode = True
_SPEC = importlib.util.spec_from_file_location("testflight_processing", PROCESSING)
asc = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(asc)
Refused, Unreachable = asc.Refused, asc.Unreachable


def annotate(kind, message):
    print(f"::{kind} title=Game Center setup::{message}", flush=True)


# --- The data -------------------------------------------------------------

def load(path=DATA):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    problems = []
    ids = [item["vendorIdentifier"] for item in data["leaderboards"] + data["achievements"]]
    for duplicate in sorted({i for i in ids if ids.count(i) > 1}):
        problems.append(f"{duplicate} is listed twice")
    names = [item["referenceName"] for item in data["achievements"]]
    for duplicate in sorted({n for n in names if names.count(n) > 1}):
        problems.append(f"the reference name {duplicate} is used twice")
    points = sum(item["points"] for item in data["achievements"])
    if points > POINTS_LIMIT:
        problems.append(f"the achievements add up to {points} points; Game Center allows {POINTS_LIMIT}")
    for item in data["leaderboards"] + data["achievements"]:
        locales = [entry["locale"] for entry in item["localizations"]]
        if sorted(locales) != sorted(LOCALE_NAMES):
            problems.append(f"{item['vendorIdentifier']} has the languages {locales}")
    if problems:
        raise SystemExit("docs/game-center/game-center.json: " + "; ".join(problems))
    return data


def image_path(achievement, data_path=DATA):
    return Path(data_path).parent / achievement["image"]


def recurrence_start(recurrence, now):
    """The next Monday 00:00 in the leaderboard's time zone after `now`, in UTC."""
    if recurrence["start"] != "next Monday 00:00":
        raise SystemExit(f"unknown recurrence start {recurrence['start']!r}")
    zone = datetime.timezone(datetime.timedelta(hours=recurrence["utcOffsetHours"]))
    local = now.astimezone(zone)
    days = (7 - local.weekday()) % 7 or 7
    start = (local + datetime.timedelta(days=days)).replace(hour=0, minute=0, second=0, microsecond=0)
    return start.astimezone(datetime.timezone.utc)


def iso(moment):
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


# --- The tables in docs/GAME_CENTER_SETUP.md ---------------------------------

def doc_tables(data):
    leaderboard = data["leaderboards"][0]
    sort = {"ASC": "**Low to High**（天數越少越前面）", "DESC": "**High to Low**"}[leaderboard["scoreSortType"]]
    submission = {"BEST_SCORE": "**Best Score**", "MOST_RECENT_SCORE": "**Most Recent Score**"}
    weeks = {"P7D": "**1 Week**"}
    rules = {"FREQ=WEEKLY;INTERVAL=1": "**1 Week**"}
    recurrence = leaderboard["recurrence"]
    fields = [
        "| 欄位 | 內容 |",
        "| --- | --- |",
        f"| Reference Name | `{leaderboard['referenceName']}` |",
        f"| Leaderboard ID | `{leaderboard['vendorIdentifier']}` |",
        f"| Score Format Type | **{leaderboard['defaultFormatter'].title()}** |",
        f"| Submission Type | {submission[leaderboard['submissionType']]} |",
        f"| Sort Order | {sort} |",
        f"| Score Range | 最小 `{leaderboard['scoreRangeStart']}`、最大 `{leaderboard['scoreRangeEnd']}`（最長的挑戰是 3 年） |",
        "| Start Date | 執行那天之後的**下一個星期一 00:00（台灣時間）**（UTC 是前一天星期日 16:00） |",
        f"| Duration | {weeks[recurrence['duration']]} |",
        f"| Restarts Every | {rules[recurrence['rule']]} |",
    ]
    localizations = ["| 語言 | Display Name | Score Format | Formatter Suffix（單數／複數） |",
                     "| --- | --- | --- | --- |"]
    for entry in leaderboard["localizations"]:
        localizations.append(
            f"| {LOCALE_NAMES[entry['locale']]} | `{entry['name']}` | Integer | "
            f"`{entry['formatterSuffixSingular']}` ／ `{entry['formatterSuffix']}` |")
    achievements = ["| # | ID | 點數 | 隱藏 | 中文名稱 | 中文說明 | 英文名稱 | 英文說明 |",
                    "| --: | --- | --: | --- | --- | --- | --- | --- |"]
    for number, item in enumerate(data["achievements"], 1):
        text = {entry["locale"]: entry for entry in item["localizations"]}
        achievements.append(
            f"| {number} | `{item['vendorIdentifier']}` | {item['points']} | "
            f"{'否' if item['showBeforeEarned'] else '是'} | {text['zh-Hant']['name']} | "
            f"{text['zh-Hant']['description']} | {text['en-US']['name']} | {text['en-US']['description']} |")
    return {"leaderboard": "\n".join(fields), "leaderboard-localizations": "\n".join(localizations),
            "achievements": "\n".join(achievements)}


def render_doc(text, data):
    for name, table in doc_tables(data).items():
        begin, end = DOC_BEGIN.format(name=name), DOC_END.format(name=name)
        head, found, rest = text.partition(begin)
        _, found_end, tail = rest.partition(end)
        if not found or not found_end:
            raise SystemExit(f"docs/GAME_CENTER_SETUP.md has no {name} block")
        text = f"{head}{begin}\n{table}\n{end}{tail}"
    return text


# --- Reading App Store Connect ----------------------------------------------

class Store:
    """The App Store Connect requests this tool sends. Writes go only through `write`."""

    def __init__(self, client, apply):
        self.client = client
        self.apply = apply
        self.writes = 0

    def get(self, path, query=None):
        return asc.asking_again(lambda: self.client.request("GET", path, query), 5)

    def get_all(self, path, query=None):
        """Every page of a list; returns (data, included)."""
        data, included = [], []
        while True:
            page = self.get(path, query)
            data += page.get("data") or []
            included += page.get("included") or []
            following = (page.get("links") or {}).get("next")
            if not following:
                return data, included
            parts = urllib.parse.urlsplit(following)
            base = urllib.parse.urlsplit(self.client.base_url)
            if (parts.scheme, parts.netloc) != (base.scheme, base.netloc):
                raise Refused("App Store Connect gave a next page on another host")
            path, query = parts.path, dict(urllib.parse.parse_qsl(parts.query))

    def write(self, method, path, body):
        if not self.apply:
            raise AssertionError("a dry run must not write")
        self.writes += 1
        # Not asked again: a lost answer may hide a write that went through; a
        # second run finds it and skips it.
        return self.client.request(method, path, body=body)


def latest_version(resource, included, kind):
    ids = {item["id"] for item in ((resource.get("relationships") or {}).get("versions") or {}).get("data") or []}
    versions = [item for item in included if item.get("type") == kind and item["id"] in ids]
    if not versions:
        return None
    return max(versions, key=lambda item: (item.get("attributes") or {}).get("version") or 0)


def game_center_detail(store, app_id):
    try:
        answer = store.get(f"/v1/apps/{app_id}/gameCenterDetail")
    except Refused as error:
        if " 404" in str(error):
            answer = {}
        else:
            raise
    detail = answer.get("data")
    if not detail:
        raise Refused("this app has no Game Center in App Store Connect yet; do step 2 of "
                      "docs/GAME_CENTER_SETUP.md (App Store Connect → the app → Game Center) first")
    return detail["id"]


def differences(wanted, actual, keys):
    return [f"{key} is {actual.get(key)!r}, the table says {wanted.get(key)!r}"
            for key in keys if key in wanted and str(actual.get(key)) != str(wanted.get(key))]


def read_localizations(store, path, with_image):
    query = {"limit": "50"}
    if with_image:
        query["include"] = "image"
    data, included = store.get_all(path, query)
    images = {item["id"]: item for item in included if item.get("type") == "gameCenterAchievementImages"}
    found = {}
    for item in data:
        attributes = item.get("attributes") or {}
        image = ((item.get("relationships") or {}).get("image") or {}).get("data")
        found[attributes.get("locale")] = {"id": item["id"], "attributes": attributes,
                                           "image": images.get(image["id"], image) if image else None}
    return found


LEADERBOARD_KEYS = ("referenceName", "defaultFormatter", "submissionType", "scoreSortType",
                    "scoreRangeStart", "scoreRangeEnd")
ACHIEVEMENT_KEYS = ("referenceName", "points", "showBeforeEarned", "repeatable")


def plan_item(store, wanted, existing, included, kind, data_path):
    """What to do for one leaderboard or achievement: a dict the apply step follows."""
    achievement = kind == "achievement"
    plan = {"kind": kind, "wanted": wanted, "notes": [], "create": False, "id": None,
            "version": None, "locales": [], "images": {}}
    if achievement and not image_path(wanted, data_path).is_file():
        plan["skip"] = f"the image {wanted['image']} is not in the repository yet (pull request #1158)"
        return plan
    plan["skip"] = None
    remote = existing.get(wanted["vendorIdentifier"])
    if remote is None:
        plan["create"] = True
        plan["locales"] = [entry["locale"] for entry in wanted["localizations"]]
        if achievement:
            plan["images"] = {locale: None for locale in plan["locales"]}
        return plan

    plan["id"] = remote["id"]
    attributes = remote.get("attributes") or {}
    keys = ACHIEVEMENT_KEYS if achievement else LEADERBOARD_KEYS
    plan["notes"] += differences(wanted, attributes, keys)
    if not achievement:
        recurrence = wanted["recurrence"]
        plan["notes"] += differences({"recurrenceDuration": recurrence["duration"],
                                      "recurrenceRule": recurrence["rule"]}, attributes,
                                     ("recurrenceDuration", "recurrenceRule"))
    if attributes.get("archived"):
        plan["notes"].append("it is archived")
        return plan
    version_kind = "gameCenterAchievementVersions" if achievement else "gameCenterLeaderboardVersions"
    version = latest_version(remote, included, version_kind)
    if version is None:
        plan["notes"].append("App Store Connect lists no version of it")
        return plan
    state = (version.get("attributes") or {}).get("state")
    plan["version"] = version["id"]
    path = f"/v2/{version_kind}/{version['id']}/localizations"
    have = read_localizations(store, path, achievement)
    for entry in wanted["localizations"]:
        found = have.get(entry["locale"])
        if found:
            texts = {"name": entry["name"]}
            if achievement:
                texts.update(beforeEarnedDescription=entry["description"], afterEarnedDescription=entry["description"])
            plan["notes"] += [f"{entry['locale']}: {note}"
                              for note in differences(texts, found["attributes"], tuple(texts))]
    missing = [entry["locale"] for entry in wanted["localizations"] if entry["locale"] not in have]
    need_images = {}
    if achievement:
        for locale, found in have.items():
            if locale not in LOCALE_NAMES:
                continue
            image = found["image"]
            if image is None:
                need_images[locale] = found["id"]
            else:
                delivery = (((image.get("attributes") or {}).get("assetDeliveryState") or {}).get("state"))
                if delivery and delivery not in ("COMPLETE", "UPLOAD_COMPLETE"):
                    plan["notes"].append(f"{locale}: its image is {delivery}; not touched (fix it in App Store Connect)")
        need_images.update({locale: None for locale in missing})
    if (missing or need_images) and state != EDITABLE:
        plan["notes"].append(f"its version is {state}, so the missing languages or images are not added")
        return plan
    plan["locales"] = missing
    plan["images"] = need_images
    return plan


def read_plan(store, app_id, data, only, data_path):
    detail = game_center_detail(store, app_id)
    plans = []
    if only in ("all", "leaderboards"):
        remote, included = store.get_all(f"/v1/gameCenterDetails/{detail}/gameCenterLeaderboardsV2",
                                         {"include": "versions", "limit": "200"})
        existing = {(item.get("attributes") or {}).get("vendorIdentifier"): item for item in remote}
        plans += [plan_item(store, item, existing, included, "leaderboard", data_path)
                  for item in data["leaderboards"]]
    if only in ("all", "achievements"):
        remote, included = store.get_all(f"/v1/gameCenterDetails/{detail}/gameCenterAchievementsV2",
                                         {"include": "versions", "limit": "200"})
        existing = {(item.get("attributes") or {}).get("vendorIdentifier"): item for item in remote}
        plans += [plan_item(store, item, existing, included, "achievement", data_path)
                  for item in data["achievements"]]
    return detail, plans


# --- The list -------------------------------------------------------------

def describe(plan, start):
    wanted = plan["wanted"]
    name = "排行榜" if plan["kind"] == "leaderboard" else "成就"
    head = f"{name} `{wanted['vendorIdentifier']}`"
    if plan["skip"]:
        return [f"- {head}：先不建，{plan['skip']}"]
    texts = {entry["locale"]: entry for entry in wanted["localizations"]}
    if plan["create"]:
        if plan["kind"] == "leaderboard":
            what = (f"新建：{wanted['referenceName']}，{wanted['defaultFormatter']}、{wanted['submissionType']}、"
                    f"{wanted['scoreSortType']}、{wanted['scoreRangeStart']}–{wanted['scoreRangeEnd']}，"
                    f"從 {iso(start)}（台灣時間星期一 00:00）起每 {wanted['recurrence']['duration']} 一期"
                    f"（{wanted['recurrence']['rule']}）")
        else:
            what = (f"新建：{wanted['referenceName']}，{wanted['points']} 點，"
                    f"{'不隱藏' if wanted['showBeforeEarned'] else '隱藏'}，"
                    f"{'可重複' if wanted['repeatable'] else '不可重複'}")
    else:
        what = "已經有了，不動"
    lines = [f"- {head}：{what}"]
    for locale in plan["locales"]:
        entry = texts[locale]
        detail = f"「{entry['name']}」"
        if plan["kind"] == "achievement":
            detail += f"，說明「{entry['description']}」"
        else:
            detail += f"，單位「{entry['formatterSuffixSingular']}」／「{entry['formatterSuffix']}」"
        lines.append(f"  - 加語言 {locale}：{detail}")
    for locale in plan["images"]:
        lines.append(f"  - 上傳 {locale} 的圖：docs/game-center/{wanted['image']}")
    lines += [f"  - 注意（不會改）：{note}" for note in plan["notes"]]
    return lines


def counts(plans):
    new = sum(1 for plan in plans if not plan["skip"] and plan["create"])
    locales = sum(len(plan["locales"]) for plan in plans if not plan["skip"])
    images = sum(len(plan["images"]) for plan in plans if not plan["skip"])
    waiting = sum(1 for plan in plans if plan["skip"])
    return new, locales, images, waiting


# --- Creating -------------------------------------------------------------

def first_version(store, kind, resource_id):
    path = f"/v2/{kind}/{resource_id}/versions"
    versions = store.get(path, {"limit": "10"}).get("data") or []
    if not versions:
        raise Refused(f"App Store Connect gave no version for the new {kind[:-1]} {resource_id}")
    return max(versions, key=lambda item: (item.get("attributes") or {}).get("version") or 0)["id"]


def create_leaderboard(store, detail, wanted, start):
    recurrence = wanted["recurrence"]
    attributes = {key: wanted[key] for key in LEADERBOARD_KEYS + ("vendorIdentifier",)}
    attributes.update(recurrenceStartDate=iso(start), recurrenceDuration=recurrence["duration"],
                      recurrenceRule=recurrence["rule"])
    body = {"data": {"type": "gameCenterLeaderboards", "attributes": attributes, "relationships": {
                "gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail}},
                "versions": {"data": [{"type": "gameCenterLeaderboardVersions", "id": "${version}"}]}}},
            "included": [{"type": "gameCenterLeaderboardVersions", "id": "${version}"}]}
    return store.write("POST", "/v2/gameCenterLeaderboards", body)["data"]["id"]


def create_achievement(store, detail, wanted):
    attributes = {key: wanted[key] for key in ACHIEVEMENT_KEYS + ("vendorIdentifier",)}
    body = {"data": {"type": "gameCenterAchievements", "attributes": attributes, "relationships": {
                "gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail}},
                "versions": {"data": [{"type": "gameCenterAchievementVersions", "id": "${version}"}]}}},
            "included": [{"type": "gameCenterAchievementVersions", "id": "${version}"}]}
    return store.write("POST", "/v2/gameCenterAchievements", body)["data"]["id"]


def create_localization(store, plan, version, entry):
    if plan["kind"] == "leaderboard":
        kind, version_kind = "gameCenterLeaderboardLocalizations", "gameCenterLeaderboardVersions"
        attributes = {"locale": entry["locale"], "name": entry["name"],
                      "formatterSuffix": entry["formatterSuffix"],
                      "formatterSuffixSingular": entry["formatterSuffixSingular"]}
    else:
        kind, version_kind = "gameCenterAchievementLocalizations", "gameCenterAchievementVersions"
        attributes = {"locale": entry["locale"], "name": entry["name"],
                      "beforeEarnedDescription": entry["description"],
                      "afterEarnedDescription": entry["description"]}
    body = {"data": {"type": kind, "attributes": attributes, "relationships": {
        "version": {"data": {"type": version_kind, "id": version}}}}}
    return store.write("POST", f"/v2/{kind}", body)["data"]["id"]


def upload(operation, payload):
    """One part of an image to the address App Store Connect gave; it carries no token."""
    offset, length = operation.get("offset") or 0, operation.get("length") or len(payload)
    request = urllib.request.Request(operation["url"], data=payload[offset:offset + length],
                                     method=operation.get("method") or "PUT")
    for header in operation.get("requestHeaders") or []:
        request.add_header(header["name"], header["value"])
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            response.read()
    except urllib.error.HTTPError as error:
        raise Refused(f"the image upload was answered with HTTP {error.code}") from None
    except (urllib.error.URLError, OSError) as error:
        raise Unreachable(f"the image upload got no answer: {getattr(error, 'reason', error)}") from None


def create_image(store, localization, path):
    payload = path.read_bytes()
    body = {"data": {"type": "gameCenterAchievementImages",
                     "attributes": {"fileName": path.name, "fileSize": len(payload)},
                     "relationships": {"localization": {"data": {
                         "type": "gameCenterAchievementLocalizations", "id": localization}}}}}
    image = store.write("POST", "/v2/gameCenterAchievementImages", body)["data"]
    operations = (image.get("attributes") or {}).get("uploadOperations") or []
    if not operations:
        raise Refused("App Store Connect gave no upload address for the image")
    for operation in operations:
        upload(operation, payload)
    store.write("PATCH", f"/v2/gameCenterAchievementImages/{image['id']}",
                {"data": {"type": "gameCenterAchievementImages", "id": image["id"],
                          "attributes": {"uploaded": True}}})


def carry_out(store, detail, plan, start, data_path):
    wanted = plan["wanted"]
    texts = {entry["locale"]: entry for entry in wanted["localizations"]}
    leaderboard = plan["kind"] == "leaderboard"
    version = plan["version"]
    if plan["create"]:
        if leaderboard:
            plan["id"] = create_leaderboard(store, detail, wanted, start)
        else:
            plan["id"] = create_achievement(store, detail, wanted)
        print(f"建好了：{wanted['vendorIdentifier']}", flush=True)
        version = first_version(store, "gameCenterLeaderboards" if leaderboard else "gameCenterAchievements",
                                plan["id"])
    localizations = dict(plan["images"])
    for locale in plan["locales"]:
        localizations[locale] = create_localization(store, plan, version, texts[locale])
        print(f"  加了語言 {locale}", flush=True)
    for locale in plan["images"]:
        create_image(store, localizations[locale], image_path(wanted, data_path))
        print(f"  上傳了 {locale} 的圖", flush=True)


# --- Running --------------------------------------------------------------

def write_summary(lines):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as summary:
            summary.write("\n".join(lines) + "\n")


def explain(error):
    text = str(error)
    if " 401" in text:
        return text + "。App Store Connect 不認得這把 key：看 docs/GAME_CENTER_SETUP.md 的「權限不夠或 key 不對」"
    if " 403" in text:
        return (text + "。這把 key 的角色不能建 Game Center 的項目，要 Admin 或 App Manager："
                "看 docs/GAME_CENTER_SETUP.md 的「權限不夠或 key 不對」")
    return text


def run(client, app_id, apply, only, data, data_path=DATA, now=None):
    store = Store(client, apply)
    start = recurrence_start(data["leaderboards"][0]["recurrence"],
                             now or datetime.datetime.now(datetime.timezone.utc))
    try:
        detail, plans = read_plan(store, app_id, data, only, data_path)
    except (Refused, Unreachable) as error:
        annotate("error", explain(error))
        return 1, store
    new, locales, images, waiting = counts(plans)
    title = "會建立的項目（apply）" if apply else "dry run：apply 會建立的項目"
    lines = [f"### Game Center：{title}", "",
             f"新的項目 {new} 個、語言 {locales} 個、圖 {images} 張；先不建 {waiting} 個。", ""]
    for plan in plans:
        lines += describe(plan, start)
    print("\n".join(lines), flush=True)
    write_summary(lines)
    if not apply:
        print("\n這是 dry run：只讀了 App Store Connect，沒有建立或修改任何東西。"
              "清單沒問題，再選 apply 跑一次。", flush=True)
        return 0, store
    if not (new or locales or images):
        print("\n沒有要建立的東西。", flush=True)
        return 0, store
    print("\n開始建立。", flush=True)
    for plan in plans:
        if plan["skip"]:
            continue
        try:
            carry_out(store, detail, plan, start, data_path)
        except (Refused, Unreachable) as error:
            annotate("error", f"{plan['wanted']['vendorIdentifier']}：{explain(error)}。"
                     "前面建好的會留著；修好之後再跑一次，已經有的會跳過。")
            write_summary(["", f"**停在 `{plan['wanted']['vendorIdentifier']}`**：{explain(error)}"])
            return 1, store
    print("\n全部建好了。", flush=True)
    write_summary(["", "**全部建好了。**"])
    return 0, store


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--apply", action="store_true", help="create what is missing (default: a dry run)")
    parser.add_argument("--only", choices=("all", "leaderboards", "achievements"), default="all")
    parser.add_argument("--write-doc", action="store_true", help="rewrite the tables in GAME_CENTER_SETUP.md")
    parser.add_argument("--check-doc", action="store_true", help="fail when those tables differ from the JSON")
    args = parser.parse_args(argv)
    data = load()

    if args.write_doc or args.check_doc:
        text = DOC.read_text(encoding="utf-8")
        rendered = render_doc(text, data)
        if args.write_doc:
            DOC.write_text(rendered, encoding="utf-8")
            return 0
        if rendered != text:
            print("docs/GAME_CENTER_SETUP.md differs from docs/game-center/game-center.json; "
                  "run tools/game-center-setup/game_center_setup.py --write-doc", file=sys.stderr)
            return 1
        print("docs/GAME_CENTER_SETUP.md matches docs/game-center/game-center.json.")
        return 0

    missing = [name for name in REQUIRED if not os.environ.get(name)]
    for name in missing:
        annotate("error", f"{name} is not set.")
    if missing:
        return 1
    with tempfile.TemporaryDirectory() as folder:
        key_path = Path(folder) / "key.p8"
        # Drop CR line endings and leading blank lines a paste may have added.
        key_text = os.environ["ASC_PRIVATE_KEY"].replace("\r", "").lstrip("\n") + "\n"
        descriptor = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as key_file:
            key_file.write(key_text)
        client = asc.Client(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], key_path,
                            os.environ.get("ASC_API_URL") or asc.API_URL)
        status, _ = run(client, os.environ["ASC_APP_ID"], args.apply, args.only, data)
    return status


if __name__ == "__main__":
    sys.exit(main())
