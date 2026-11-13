#!/bin/sh
# Decision 725: downloads the KMZ files tools/tpe-temples/recipes.mjs reads
# from the Taipei City Government Department of Civil Affairs' 臺北市宗教建築
# 3D 模型庫 (https://data.gov.tw/dataset/121136; its CSV lists each temple's
# link, https://canet.civil.taipei/tp90-1/model/<number>.kmz), checks each
# against the copy the models were made from, and unzips it.
#
#   sh tools/tpe-temples/fetch.sh <folder>
#
# Then: node tools/tpe-temples/build.mjs <folder>/x <output folder>
# The KMZ files are not committed (the eleven are about 40 MB, the whole
# dataset 237 MB).
set -eu
folder=${1:?usage: fetch.sh <folder>}
mkdir -p "$folder/x"
cd "$folder"
while read -r sum file; do
  [ -f "$file" ] || curl -fsS --retry 3 -o "$file" "https://canet.civil.taipei/tp90-1/model/$file"
  echo "$sum  $file" | sha256sum -c -
  name=${file%.kmz}
  rm -rf "x/$name" && mkdir -p "x/$name" && unzip -q "$file" -d "x/$name"
done <<'SUMS'
90eab10eb54d8da59cbf15872d4646579c521fee46af1ecb428e1aa692e6e22f  100001.kmz
e24ba176ea8169b81d8ecff9a0920db4ef0591e9e79d8e69de89cc60e44c0e3e  100005.kmz
25ccdc99fc2b8fa451e16f91491c17e3b7953731603d0650f889571317d2eca3  103002.kmz
8cf02c82a4da862d77e5c6a3ffa155ac2a3b3f7b4842fd273b9e8387da848e7d  104001.kmz
0466b1b418d55d1d56bfeade7ff092e8a03d76bf85ed47ec6a1e685923205b48  108001.kmz
88f6b81d3f08f1d9b7e55ab3ea7fa4797fb9ad0f8b1c752709bf7c931604c89a  108003.kmz
577c94238e3d30cc1871adf87445d5a87cffa939dee946f9e458f48b6139f6af  108003A.kmz
cabab22af70fb632cd9b12f62bf361481ce9c7f4aa04b0bb296799a32de140e8  108004.kmz
915b42e8b92ae01777d7bb2de30ae24df6e9810b92d948bb949610b527764204  111001_01.kmz
ec56b2f1c4a347eed42f50a619990bc26faf90fc4a2242f5d4f752523c82076e  111003.kmz
e38a6b712412bcb8782e83ffc1c0e431dd198063b53f10b6d3a888a283cc495b  116001.kmz
SUMS
