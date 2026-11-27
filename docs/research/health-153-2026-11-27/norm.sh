#!/bin/bash
grep "^DEPOT_RETURN" "$1" | sed -E 's/[,;] [0-9]+ s$//'
