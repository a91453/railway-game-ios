"""Tests of the ridership tools on small made-up files (no network).

    python3 -I tools/real-ridership/test_tools.py
"""

import calendar
import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))


def run(tool, *arguments):
    return subprocess.run([sys.executable, "-I", os.path.join(HERE, tool), *arguments], capture_output=True, text=True)


def write_json(path, value):
    with open(path, "w", encoding="utf-8") as file:
        json.dump(value, file, ensure_ascii=False)


class TaoyuanTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.stations = os.path.join(self.folder, "tymc.json")
        write_json(self.stations, {"lines": [{"name": "機場捷運", "stations": [{"name": "台北車站"}, {"name": "三重站"}, {"name": "老街溪站"}]}]})
        self.files = os.path.join(self.folder, "files")
        os.mkdir(self.files)

    def month(self, month, rows, year="114", total=None):
        """A month as pdftotext -layout writes it: rows of (code name, entries, exits)."""
        entries = sum(row[1] for row in rows)
        exits = sum(row[2] for row in rows)
        lines = ["              桃園大眾捷運股份有限公司", f"營運月份：{year}年{month}月                     單位：人次",
                 "                        各站旅運量", "捷運站別                    入站                出站"]
        lines += [f"{name}               {a:,}           {b:,}" for name, a, b in rows]
        lines += [f"總計                   {(total or (entries, exits))[0]:,}         {(total or (entries, exits))[1]:,}",
                  "團體票                            2,954", "其他                             1,087"]
        with open(os.path.join(self.files, f"2025-{month:02d}.txt"), "w", encoding="utf-8") as file:
            file.write("\n".join(lines) + "\n")

    def year(self, a1=lambda month: 20_000):
        for month in range(1, 13):
            self.month(month, [("A1 台北車站", a1(month), a1(month)), ("A2 三重站", 3000, 1000)])

    def build(self):
        output = os.path.join(self.folder, "out.json")
        result = run("build_tymc_ridership.py", "--year", "2025", "--downloaded", "2026-10-21",
                     "--stations", self.stations, "--output", output, "--files", self.files)
        return result, (json.load(open(output, encoding="utf-8")) if result.returncode == 0 else None)

    def test_a_year_is_entries_and_exits_halved_over_its_days(self):
        # January's entries and exits at 36,500 each, the other months' at 0.
        self.year(lambda month: 36_500 if month == 1 else 0)
        result, output = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output["riders"]["台北車站"], 100)
        self.assertEqual(output["riders"]["三重站"], round(12 * 4000 / 2 / 365))
        self.assertEqual(output["period"], {"from": "2025-01-01", "to": "2025-12-31"})
        self.assertEqual(len(output["source"]["fileSha256"]), 12)
        self.assertIn("names the app does not have: none", result.stdout)
        self.assertIn("stations of the app with no data: 老街溪站", result.stdout)

    def test_a_missing_month_or_a_wrong_month_is_refused(self):
        self.year()
        os.remove(os.path.join(self.files, "2025-12.txt"))
        self.assertNotEqual(self.build()[0].returncode, 0)
        self.year()
        self.month(1, [("A1 台北車站", 1, 1)], year="113")
        self.assertNotEqual(self.build()[0].returncode, 0)

    def test_a_total_row_the_stations_do_not_add_up_to_is_refused(self):
        self.year()
        self.month(3, [("A1 台北車站", 10, 10)], total=(11, 10))
        result, _ = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("total row", result.stderr)


class TaichungTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.stations = os.path.join(self.folder, "tmrt.json")
        write_json(self.stations, {"lines": [{"name": "綠線", "stations": [{"name": "北屯總站"}, {"name": "市政府"}, {"name": "高鐵臺中站"}]}]})

    def month(self, month, exits, entries=None):
        item = "捷運各站旅運量-{}人數(人次)(單位:人次)"
        rows = [{"項目": item.format("出站"), "欄位名稱": name, "數值": str(count), "資料時間日期": f"2025-{month:02d}-01T00:00:00"} for name, count in exits.items()]
        rows += [{"項目": item.format("入站"), "欄位名稱": name, "數值": str(count), "資料時間日期": f"2025-{month:02d}-01T00:00:00"} for name, count in (entries or {}).items()]
        rows.append({"項目": item.format("其他出站"), "欄位名稱": "", "數值": "5", "資料時間日期": f"2025-{month:02d}-01T00:00:00"})
        write_json(os.path.join(self.folder, f"2025-{month:02d}.json"), rows)

    def build(self, *extra):
        output = os.path.join(self.folder, "out.json")
        result = run("build_tmrt_ridership.py", "--year", "2025", "--downloaded", "2026-10-20", "--stations", self.stations,
                     "--output", output, "--files", self.folder, *extra)
        return result, (json.load(open(output, encoding="utf-8")) if result.returncode == 0 else None)

    def test_exits_of_the_listed_months_over_their_days(self):
        self.month(2, {"北屯總站": 280, "市政府站": 2800, "高鐵臺中站": 28_000})
        self.month(4, {"北屯總站": 300, "市政府站": 3000, "高鐵臺中站": 30_000})
        result, _ = self.build()
        self.assertNotEqual(result.returncode, 0, "a part of a year needs --partial")
        result, output = self.build("--partial")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output["months"], ["2025-02", "2025-04"])
        self.assertEqual(output["riders"], {"北屯總站": 10, "市政府": 100, "高鐵臺中站": 1000})
        self.assertIn("exits", output["measure"])
        self.assertIn("names the app does not have: none", result.stdout)

    def test_entries_and_exits_are_halved_when_every_month_has_both(self):
        self.month(2, {"市政府站": 2800}, entries={"市政府站": 5600})
        result, output = self.build("--partial")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output["riders"]["市政府"], 150)


def ods(path, entries, exits, days):
    """A New Taipei Metro month: {code: (name, count a day)} for each kind."""
    def sheet(name, stations):
        def row(cells):
            return "<table:table-row>" + "".join(cells) + "</table:table-row>"
        def text(value):
            return f'<table:table-cell office:value-type="string"><text:p>{value}</text:p></table:table-cell>'
        def number(value, repeated=1):
            return f'<table:table-cell office:value-type="float" office:value="{value}" table:number-columns-repeated="{repeated}"><text:p>{value}</text:p></table:table-cell>'
        body = row([text("日期")] + [text(f"{day}日") for day in range(1, days + 1)] + [text("總計")])
        for code, (station, count) in stations.items():
            body += row([text(code), text(station), number(count, days), number(count * days), text(code)])
        return f'<table:table table:name="{name}">{body}</table:table>'
    content = "<office:document-content><office:body><office:spreadsheet>" + sheet("每日運量(進站)", entries) + sheet("每日運量(出站)", exits) + "</office:spreadsheet></office:body></office:document-content>"
    with zipfile.ZipFile(path, "w") as file:
        file.writestr("content.xml", content)


class NewTaipeiTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()
        self.app = os.path.join(self.folder, "app")
        os.mkdir(self.app)
        write_json(os.path.join(self.app, "ntdlrt.json"), {"lines": [{"name": "綠山線", "stations": [{"name": "紅樹林"}]}]})
        write_json(os.path.join(self.app, "ntalrt.json"), {"lines": [{"name": "安坑輕軌", "stations": [{"name": "十四張"}]}]})
        write_json(os.path.join(self.app, "trtc.json"), {"lines": [{"name": "板南線", "stations": [{"name": "板橋"}]}, {"name": "環狀線", "stations": [{"name": "板橋"}, {"name": "十四張"}]}]})
        write_json(os.path.join(self.app, "sanying.json"), {"lines": [{"name": "三鶯線", "stations": [{"name": "臺北大學"}]}]})
        self.files = os.path.join(self.folder, "files")
        os.mkdir(self.files)
        self.out = os.path.join(self.folder, "out")
        os.mkdir(self.out)

    def months(self, sanying_from=None):
        for offset in range(12):
            year, month = 2025 + (9 + offset) // 12, (9 + offset) % 12 + 1
            days = calendar.monthrange(year, month)[1]
            stations = {"V01": ("紅樹林站", 100), "K09": ("十四張站", 30), "Y08": ("十四張站", 50), "Y16": ("板橋站", 200)}
            if sanying_from is not None and offset >= sanying_from:
                stations["LB07"] = ("臺北大學站", 40)
            exits = {code: (name, count * 3) for code, (name, count) in stations.items()}
            ods(os.path.join(self.files, f"{year}-{month:02d}.ods"), stations, exits, days)

    def build(self, *extra):
        return run("build_ntmc_ridership.py", "--first", "2025-10", "--downloaded", "2026-10-20", "--app", self.app,
                   "--output", self.out, "--files", self.files, *extra)

    def riders(self, name):
        return json.load(open(os.path.join(self.out, name), encoding="utf-8"))["riders"]

    def test_each_line_gets_its_own_file_by_the_apps_names(self):
        self.months(sanying_from=9)
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        # (entries + exits) / 2 a day: (100 + 300) / 2.
        self.assertEqual(self.riders("ntdlrt_ridership.json"), {"紅樹林": 200})
        self.assertEqual(self.riders("ntalrt_ridership.json"), {"十四張": 60})
        self.assertEqual(self.riders("ntmc_circular_ridership.json"), {"十四張": 100, "板橋": 400})
        # Three months of the Sanying Line are not a year.
        self.assertFalse(os.path.exists(os.path.join(self.out, "sanying_ridership.json")))
        self.assertIn("三鶯線: skipped", result.stdout)

    def test_partial_takes_a_new_line_after_its_opening_month(self):
        # The line opens in 2026-06 (offset 8): June is left out.
        self.months(sanying_from=8)
        result = self.build("--partial")
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.load(open(os.path.join(self.out, "sanying_ridership.json"), encoding="utf-8"))
        self.assertEqual(output["riders"], {"臺北大學": 80})
        self.assertEqual(output["months"], ["2026-07", "2026-08", "2026-09"])
        self.assertEqual(output["period"], {"from": "2026-07-01", "to": "2026-09-30"})
        self.assertEqual(sorted(output["source"]["fileSha256"]), output["months"])
        # A line of the whole twelve months is as without --partial.
        self.assertEqual(self.riders("ntdlrt_ridership.json"), {"紅樹林": 200})
        self.assertNotIn("months", json.load(open(os.path.join(self.out, "ntdlrt_ridership.json"), encoding="utf-8")))

    def test_a_missing_month_is_refused(self):
        self.months()
        os.remove(os.path.join(self.files, "2026-03.ods"))
        self.assertNotEqual(self.build().returncode, 0)


if __name__ == "__main__":
    unittest.main()
