#!/usr/bin/env bash
# Shared six-model roof/facade review package; see decision 669.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
exec "$root/tools/civic-kit/rebuild-roofs.sh" "${1:?usage: rebuild-roofs.sh PRIVATE_OUTPUT_DIRECTORY}"
