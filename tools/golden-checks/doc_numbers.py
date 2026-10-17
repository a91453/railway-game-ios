#!/usr/bin/env python3
"""Checks that the numbers docs/OVERVIEW.md §2 states match the repository
(docs/HANDOFF.md §2, "核心玩法：回饋 → 開發工具"; §7.4).

Compared:
- the save version with `SavedGame.currentVersion`
  (Sources/GameCore/World/SavedGame.swift);
- the save fixtures with the JSON files in SaveFixtures/;
- the golden schema with `GoldenScenario.schemaVersion`
  (Tests/GameCoreTests/GoldenScenario.swift);
- the golden fixtures with the JSON files in GoldenScenarios/;
- the replay fixtures with the JSON files in ReplayFixtures/;
- the last decision with the largest `### N.` in docs/ARCHITECTURE.md.

Only a directory's own JSON files are counted, as the tests that read them
do (ReplayFixtures/Reports/ is not a replay fixture).

The decisions: every `### N.` heading of docs/ARCHITECTURE.md appears once,
every one has a row in the decision index (OVERVIEW §9; ARCHITECTURE points
to it) and every row there has its heading. Headings or rows out of order,
the numbers missing below the last one and the continuation headings
(`### 204（續）.`) are listed as notes; they are not differences.

Python 3 standard library only:
    python3 -I tools/golden-checks/doc_numbers.py            # report
    python3 -I tools/golden-checks/doc_numbers.py --check    # exit 1 on a difference
    python3 -I tools/golden-checks/doc_numbers.py --selftest
"""
import argparse
import pathlib
import re
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]

OVERVIEW = "docs/OVERVIEW.md"
ARCHITECTURE = "docs/ARCHITECTURE.md"
SAVED_GAME = "Sources/GameCore/World/SavedGame.swift"
GOLDEN_SCENARIO = "Tests/GameCoreTests/GoldenScenario.swift"

HEADING = re.compile(r"^### (\d+)\.(?:\s|$)")
CONTINUATION = re.compile(r"^### (\d+)（[^）]*）\.")
UNUSED = "沒有使用"


def section(text, number):
    """The lines of `## <number>.` up to the next `## ` heading."""
    lines, inside = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            if inside:
                break
            inside = line.startswith(f"## {number}.")
            continue
        if inside:
            lines.append(line)
    return lines


def table_rows(lines):
    """The cells of a Markdown table's body rows."""
    rows = []
    for line in lines:
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-+:?", cell) for cell in cells if cell):
            continue
        rows.append(cells)
    return rows[1:] if rows else rows


def first(pattern, text):
    match = re.search(pattern, text) if text is not None else None
    return int(match.group(1)) if match else None


def overview_numbers(text):
    """What OVERVIEW §2 states, by item; `None` where it cannot be read."""
    cells = {row[0]: row[1] for row in table_rows(section(text, 2)) if len(row) >= 2}
    save, golden, replay, decisions = (cells.get(name) for name in ("存檔版本", "golden", "replay", "決策"))
    last = None
    if decisions is not None:
        # "1–217、219–265（218 沒有使用…）": the ranges before the remarks.
        numbers = [int(n) for n in re.findall(r"\d+", decisions.split("（")[0])]
        last = max(numbers) if numbers else None
    return {
        "save_version": first(r"^\s*(\d+)", save),
        "save_fixtures": first(r"共\s*(\d+)\s*個", save),
        "golden_schema": first(r"schema\s*(\d+)", golden),
        "golden_fixtures": first(r"(\d+)\s*個\s*JSON", golden),
        "replay_fixtures": first(r"^\s*(\d+)\s*個", replay),
        "last_decision": last,
    }


def headings(text):
    """(number, line) of each `### N.` heading outside code fences, and the
    continuation headings' lines."""
    found, continued, fenced = [], [], False
    for index, line in enumerate(text.splitlines(), 1):
        if line.startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        if match := HEADING.match(line):
            found.append((int(match.group(1)), index))
        elif match := CONTINUATION.match(line):
            continued.append((line[4:].split(".")[0], index))
    return found, continued


def index_rows(text):
    """(number, title) of each row of OVERVIEW §9's table, in order."""
    return [(int(row[0]), row[1] if len(row) > 1 else "") for row in table_rows(section(text, 9)) if row and row[0].isdigit()]


def json_count(directory):
    return sum(1 for path in directory.glob("*.json") if path.is_file()) if directory.is_dir() else None


def descents(numbers, name):
    """Each number that comes after a larger one."""
    notes = []
    for previous, current in zip(numbers, numbers[1:]):
        if current[0] < previous[0]:
            notes.append(f"{name}：{current[0]} 排在 {previous[0]} 之後（第 {current[1]} {'行' if name == 'ARCHITECTURE' else '列'}）")
    return notes


def duplicates(numbers):
    seen, twice = set(), []
    for number in numbers:
        if number in seen and number not in twice:
            twice.append(number)
        seen.add(number)
    return twice


def compare(root):
    """(table, differences, notes) for the repository at `root`."""
    root = pathlib.Path(root)
    differences, notes = [], []

    def read(relative):
        path = root / relative
        if not path.is_file():
            differences.append(f"找不到 {relative}")
            return ""
        return path.read_text(encoding="utf-8")

    overview, architecture = read(OVERVIEW), read(ARCHITECTURE)
    stated = overview_numbers(overview)
    found, continued = headings(architecture)
    numbers = [number for number, _ in found]
    actual = {
        "save_version": first(r"static let currentVersion\s*=\s*(\d+)", read(SAVED_GAME)),
        "save_fixtures": json_count(root / "SaveFixtures"),
        "golden_schema": first(r"static let schemaVersion\s*=\s*(\d+)", read(GOLDEN_SCENARIO)),
        "golden_fixtures": json_count(root / "GoldenScenarios"),
        "replay_fixtures": json_count(root / "ReplayFixtures"),
        "last_decision": max(numbers) if numbers else None,
    }
    items = [
        ("save_version", "存檔版本", "SavedGame.currentVersion"),
        ("save_fixtures", "存檔 fixture 個數", "SaveFixtures/*.json"),
        ("golden_schema", "golden schema", "GoldenScenario.schemaVersion"),
        ("golden_fixtures", "golden 個數", "GoldenScenarios/*.json"),
        ("replay_fixtures", "replay 個數", "ReplayFixtures/*.json"),
        ("last_decision", "最後的決策", "ARCHITECTURE 最大的 ### N."),
    ]
    table = []
    for key, name, source in items:
        doc, code = stated[key], actual[key]
        if doc is None or code is None:
            result = "讀不到"
        else:
            result = "一致" if doc == code else "不一致"
        if result != "一致":
            differences.append(f"{name}：OVERVIEW §2 寫 {doc if doc is not None else '（讀不到）'}，{source} 是 {code if code is not None else '（讀不到）'}")
        table.append((name, doc, source, code, result))

    for number in duplicates(numbers):
        lines = "、".join(str(line) for n, line in found if n == number)
        differences.append(f"ARCHITECTURE 的 ### {number}. 出現不只一次（第 {lines} 行）")
    indexed = index_rows(overview)
    rows = [number for number, _ in indexed]
    # A row the index itself marks as never used ("（保留後沒有使用）")
    # stands for a number with no heading.
    unused = {number for number, title in indexed if UNUSED in title}
    for number in duplicates(rows):
        differences.append(f"決策索引（OVERVIEW §9）的 {number} 不只一列")
    for number in sorted(set(numbers) - set(rows)):
        differences.append(f"決策 {number} 不在決策索引（OVERVIEW §9）裡")
    for number in sorted(set(rows) - set(numbers) - unused):
        differences.append(f"決策索引（OVERVIEW §9）有 {number}，ARCHITECTURE 沒有 ### {number}.")
    for number in sorted(unused & set(numbers)):
        differences.append(f"決策索引（OVERVIEW §9）寫 {number} 沒有使用，ARCHITECTURE 卻有 ### {number}.")
    for number in sorted(unused - set(numbers)):
        notes.append(f"決策索引（OVERVIEW §9）把 {number} 列為保留後沒有使用")

    notes += descents(found, "ARCHITECTURE")
    notes += descents([(number, row) for row, number in enumerate(rows, 1)], "決策索引")
    if numbers:
        missing = sorted(set(range(1, max(numbers) + 1)) - set(numbers))
        if missing:
            notes.append("ARCHITECTURE 沒有這些號碼：" + "、".join(map(str, missing)))
    for title, line in continued:
        notes.append(f"續篇標題 ### {title}.（第 {line} 行），不算重複")
    return table, differences, notes


def report(root):
    table, differences, notes = compare(root)
    print("| 項目 | OVERVIEW §2 | 程式／檔案 | 實際 | 結果 |")
    print("| --- | --: | --- | --: | --- |")
    for name, doc, source, code, result in table:
        print(f"| {name} | {doc if doc is not None else '—'} | `{source}` | {code if code is not None else '—'} | {result} |")
    print()
    print(f"差異 {len(differences)} 項" + ("：" if differences else "。"))
    for line in differences:
        print(f"- {line}")
    print(f"附註 {len(notes)} 項（不算失敗）" + ("：" if notes else "。"))
    for line in notes:
        print(f"- {line}")
    return differences


# MARK: - Self-test

def write_repository(root, *, overview_save="63", architecture_extra="", index_extra="", replay_reports=True):
    """A small repository whose numbers all agree unless told otherwise."""
    root = pathlib.Path(root)
    files = {
        OVERVIEW: f"""# 總覽

## 2. 現況數字

| 項目 | 現在 | 在哪裡 |
| --- | --- | --- |
| 存檔版本 | {overview_save}（說明，決策 2）；每個版本一個存檔 fixture，共 2 個 | `SavedGame.currentVersion` |
| golden | schema 74（車站商業，#595），`GoldenScenarios/` 裡 3 個 JSON | `GoldenScenarios/` |
| replay | 1 個指令紀錄（含 `a.json`，#468） | `ReplayFixtures/` |
| 決策 | 1–2、4（3 沒有使用，#5）。之後以 #231 為準 | `docs/ARCHITECTURE.md` |

## 9. 決策索引

| 決策 | 標題 |
| --: | --- |
| 1 | 一 |
| 2 | 二 |
| 3 | （保留後沒有使用） |
| 4 | 四 |
{index_extra}
""",
        ARCHITECTURE: f"""# 架構

### 內部

### 1. 一

```
### 9. 程式碼裡的範例不算
```

### 2. 二

### 2（續）. 二的續篇

### 4. 四
{architecture_extra}
## 目前規則摘要
""",
        SAVED_GAME: "struct SavedGame {\n    public static let currentVersion = 63\n}\n",
        GOLDEN_SCENARIO: "struct GoldenScenario {\n    static let schemaVersion = 74\n}\n",
        "SaveFixtures/v1.json": "{}",
        "SaveFixtures/v2.json": "{}",
        "SaveFixtures/README.md": "",
        "GoldenScenarios/a.json": "{}",
        "GoldenScenarios/b.json": "{}",
        "GoldenScenarios/c.json": "{}",
        "ReplayFixtures/a.json": "{}",
    }
    if replay_reports:
        files["ReplayFixtures/Reports/report.json"] = "{}"
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def selftest():
    cases = []

    def case(name, **options):
        with tempfile.TemporaryDirectory() as directory:
            write_repository(directory, **options)
            table, differences, notes = compare(directory)
            cases.append(name)
            return table, differences, notes

    table, differences, notes = case("all agree")
    assert differences == [], differences
    assert [row[4] for row in table] == ["一致"] * 6, table
    assert [row[1] for row in table] == [63, 2, 74, 3, 1, 4], table
    assert "ARCHITECTURE 沒有這些號碼：3" in notes, notes
    assert "決策索引（OVERVIEW §9）把 3 列為保留後沒有使用" in notes, notes
    assert any("續篇標題 ### 2（續）." in note for note in notes), notes

    _, differences, _ = case("save version differs", overview_save="62")
    assert differences == ["存檔版本：OVERVIEW §2 寫 62，SavedGame.currentVersion 是 63"], differences

    _, differences, _ = case("a decision twice", architecture_extra="\n### 2. 又是二\n")
    assert any(line.startswith("ARCHITECTURE 的 ### 2. 出現不只一次") for line in differences), differences

    _, differences, _ = case("a decision not indexed", architecture_extra="\n### 5. 五\n")
    assert "決策 5 不在決策索引（OVERVIEW §9）裡" in differences, differences
    assert any(line.startswith("最後的決策：OVERVIEW §2 寫 4") for line in differences), differences

    _, differences, _ = case("an index row without its decision", index_extra="| 7 | 七 |")
    assert differences == ["決策索引（OVERVIEW §9）有 7，ARCHITECTURE 沒有 ### 7."], differences

    _, differences, notes = case("out of order is a note", architecture_extra="\n### 5. 五\n\n### 3. 三\n", index_extra="| 5 | 五 |\n| 6 | 六 |")
    assert differences == [
        "最後的決策：OVERVIEW §2 寫 4，ARCHITECTURE 最大的 ### N. 是 5",
        "決策索引（OVERVIEW §9）有 6，ARCHITECTURE 沒有 ### 6.",
        "決策索引（OVERVIEW §9）寫 3 沒有使用，ARCHITECTURE 卻有 ### 3.",
    ], differences
    assert "ARCHITECTURE：3 排在 5 之後（第 19 行）" in notes, notes

    _, differences, notes = case("index out of order is a note", index_extra="| 2 | 又在四後面 |")
    assert differences == ["決策索引（OVERVIEW §9）的 2 不只一列"], differences
    assert "決策索引：2 排在 4 之後（第 5 列）" in notes, notes


    with tempfile.TemporaryDirectory() as directory:
        write_repository(directory)
        (pathlib.Path(directory) / SAVED_GAME).unlink()
        table, differences, _ = compare(directory)
        cases.append("a file missing")
        assert f"找不到 {SAVED_GAME}" in differences and table[0][4] == "讀不到", differences

    with tempfile.TemporaryDirectory() as directory:
        write_repository(directory, overview_save="62")
        cases.append("--check exits 1 on a difference")
        assert main(["--check", "--root", directory], quiet=True) == 1
        write_repository(directory)
        assert main(["--check", "--root", directory], quiet=True) == 0
        write_repository(directory, overview_save="62")
        assert main(["--root", directory], quiet=True) == 0, "without --check it only reports"

    print(f"selftest：{len(cases)} 個情境都通過")
    return 0


def main(argv=None, quiet=False):
    parser = argparse.ArgumentParser(description="OVERVIEW §2 的數字與程式、ARCHITECTURE 的決策號是否一致。")
    parser.add_argument("--check", action="store_true", help="有差異時 exit 1")
    parser.add_argument("--selftest", action="store_true", help="用假的 repository 測這支工具")
    parser.add_argument("--root", default=str(ROOT), help="repository 的根目錄（預設：這支工具所在的 repository）")
    options = parser.parse_args(argv)
    if options.selftest:
        return selftest()
    if quiet:
        _, differences, _ = compare(options.root)
    else:
        differences = report(options.root)
    return 1 if options.check and differences else 0


if __name__ == "__main__":
    sys.exit(main())
