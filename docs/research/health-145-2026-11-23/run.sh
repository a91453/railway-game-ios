#!/bin/bash
# usage: health.sh <repo dir> <outdir> <batch: six|fuk|peo>
R=$1; O=$2; B=$3; mkdir -p $O; cd $R
T=.build/release/GamePresentationTests-test-runner
C=GamePresentationTests.DepotReturnReportTests
base="DEPOT_RETURN_REPORT=1 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_EMPTY_RUNS=1"
run(){ n=$1; shift; ( s=$(date +%s); env $base "$@" > $O/$n.log 2>&1; echo "exit=$? secs=$(( $(date +%s)-s ))" >> $O/$n.log ) & }
case $B in
six)
 run plain $T $C
 run simple DEPOT_RETURN_SIMPLE=1 $T $C
 run ctl DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 $T $C
 run plain-fast DEPOT_RETURN_FAST=1 $T $C
 run simple-fast DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_FAST=1 $T $C
 run ctl-fast DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 DEPOT_RETURN_FAST=1 $T $C ;;
fuk)
 run fuk-plain DEPOT_RETURN_ONLY=fukuoka $T $C/testFukuoka
 run fuk-simple DEPOT_RETURN_ONLY=fukuoka DEPOT_RETURN_SIMPLE=1 $T $C/testFukuoka
 run fuk-ctl DEPOT_RETURN_ONLY=fukuoka DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 $T $C/testFukuoka ;;
peo)
 run peo-tymc DEPOT_RETURN_PEOPLED=1 $T $C/testTheTaoyuanAirportLine
 run peo-tymc-ctl DEPOT_RETURN_PEOPLED=1 DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 $T $C/testTheTaoyuanAirportLine
 run peo-wenhu DEPOT_RETURN_PEOPLED=1 $T $C/testTheWenhuLine
 run peo-wenhu-ctl DEPOT_RETURN_PEOPLED=1 DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 $T $C/testTheWenhuLine ;;
esac
wait
