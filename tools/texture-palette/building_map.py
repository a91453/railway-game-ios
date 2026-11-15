"""舊版材質圖的色票分類（工作室 t003 第 2 輪）→ 遊戲建築色票的對照。

給之後「批次換一般建築」用：每張建築類的舊貼圖，對到 `Map3DPalette` 裡的哪一個陣列、
第幾個顏色（Swift 寫法），以及能不能直接用。

    python3 -I tools/texture-palette/building_map.py \
        --palette-map <t003/r2/palette-map.csv> --out tools/texture-palette/t003

輸出（只有檔名與顏色，不含本機路徑、不含貼圖）：
- building-map.csv：建築類每一張的對照與狀態；
- manual-review.csv：要人工看的屋面、地面、磚，不猜。
"""

import argparse
import collections
import csv
import os

# 色票名（t001 palette.json 的 name）→ 遊戲裡的位置。
# 來源：Sources/GamePresentation/Map3DScene.swift 的 Map3DPalette。
IN_GAME = {
    "水泥灰屋頂": "Map3DPalette.roof",
    "深灰鐵皮": "Map3DPalette.cityRoofs[1]",
    "暖灰防水層": "Map3DPalette.cityRoofs[2]",
    "綠色防水漆": "Map3DPalette.cityRoofs[3]",
    "藍色鐵皮": "Map3DPalette.cityRoofs[4]",
    "紅瓦": "Map3DPalette.cityRoofs[5]",
    "淺藍鐵皮": "Map3DPalette.hallRoofs[3]",
    "銀灰鐵皮": "Map3DPalette.hallRoofs[2]",
    "白牆": "Map3DPalette.houseWalls[0]",
    "米白": "Map3DPalette.houseWalls[1]",
    "淡粉": "Map3DPalette.houseWalls[2]",
    "淺褐": "Map3DPalette.houseWalls[3]",
    "淺黃磁磚": "Map3DPalette.houseWalls[4]",
    "淡藍灰磁磚": "Map3DPalette.houseWalls[5]",
    "淺紅磁磚": "Map3DPalette.houseWalls[6]",
    "淡綠磁磚": "Map3DPalette.houseWalls[7]",
    "辦公藍灰": "Map3DPalette.officeWalls[0]",
    "辦公淺灰": "Map3DPalette.officeWalls[1]",
    "辦公深藍灰": "Map3DPalette.officeWalls[2]",
    "米色石材": "Map3DPalette.cityOfficeWalls[3]",
    "淡藍灰": "Map3DPalette.cityOfficeWalls[4]",
    "深灰鋁板": "Map3DPalette.cityOfficeWalls[5]",
    "清水模": "Map3DPalette.concreteWalls[0]",
    "清水模深": "Map3DPalette.concreteWalls[1]",
    "清水模淺": "Map3DPalette.concreteWalls[2]",
    "暖灰水泥": "Map3DPalette.cityConcreteWalls[3]",
    "白灰水泥": "Map3DPalette.cityConcreteWalls[4]",
    "舊水泥灰": "Map3DPalette.cityConcreteWalls[5]",
    "廳舍紅磚": "Map3DPalette.hallWalls[3]",
    "米黃": "Map3DPalette.hallWalls[4]",
    "混凝土": "Map3DPalette.concrete",
    "藍色重點": "Map3DPalette.canopy",
    "月台": "Map3DPalette.platform",
}
# t001 色票裡有、遊戲裡還沒有的（b001 擴充試色與規格色）：要用就先在 PR 提出加進 Map3DPalette。
NOT_IN_GAME = {"紅磚", "洗石子", "木頭", "鋼", "深色／窗"}

BUILDING = ["整面建築立面", "清水模／水泥", "石材／洗石子／磁磚", "瓦／屋面", "磚", "金屬／鐵皮", "木頭", "玻璃／窗"]
# 作者 2026-11-15（經協調者）：這幾類整類人工看，不猜。
MANUAL = ["瓦／屋面", "地面／鋪面／草地", "磚"]


def status(row):
    if row["內容類別"] in MANUAL:
        return "人工看"
    if row["旗標"] == "主色不明":
        return "主色不明（另議）"
    if row["旗標"] == "沒有合適色票":
        return "沒有合適色票（要提新色）"
    if row["主色名"] in NOT_IN_GAME:
        return "色票未進遊戲（要提新色）"
    if row["主色名"] in IN_GAME:
        return "可直接用"
    return "另議"


def ref(name):
    return IN_GAME.get(name, "（未進遊戲）" if name in NOT_IN_GAME else "")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--palette-map", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    with open(args.palette_map, encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    os.makedirs(args.out, exist_ok=True)

    head = ["檔名", "內容類別", "狀態", "主色名", "主色hex", "主色在遊戲", "第二色名", "第二色hex", "第二色在遊戲", "原色hex", "ΔE", "面積比", "旗標"]
    building = sorted((r for r in rows if r["內容類別"] in BUILDING), key=lambda r: (BUILDING.index(r["內容類別"]), r["檔名"]))
    with open(os.path.join(args.out, "building-map.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(head)
        for r in building:
            w.writerow([r["檔名"], r["內容類別"], status(r), r["主色名"], r["主色hex"], ref(r["主色名"]),
                        r["第二色名"], r["第二色hex"], ref(r["第二色名"]), r["原色hex"], r["ΔE(CIEDE2000)"], r["面積比"], r["旗標"]])

    manual = sorted((r for r in rows if r["內容類別"] in MANUAL), key=lambda r: (MANUAL.index(r["內容類別"]), r["檔名"]))
    with open(os.path.join(args.out, "manual-review.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["檔名", "內容類別", "工具建議色", "建議色hex", "原色hex", "ΔE", "旗標", "人工判定"])
        for r in manual:
            w.writerow([r["檔名"], r["內容類別"], r["主色名"], r["主色hex"], r["原色hex"], r["ΔE(CIEDE2000)"], r["旗標"], ""])

    by_status = collections.Counter((r["內容類別"], status(r)) for r in building)
    by_colour = collections.Counter(r["主色名"] for r in building if status(r) == "可直接用")
    print("類別\t狀態\t張數")
    for (c, s), n in sorted(by_status.items(), key=lambda x: (BUILDING.index(x[0][0]), -x[1])):
        print(f"{c}\t{s}\t{n}")
    print("\n可直接用的主色\t遊戲位置\t張數")
    for name, n in by_colour.most_common():
        print(f"{name}\t{IN_GAME[name]}\t{n}")
    print("\n人工看", collections.Counter(r["內容類別"] for r in manual))


if __name__ == "__main__":
    main()
