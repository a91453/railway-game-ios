#!/bin/bash
# Claude Code cloud sessions start without Swift. Install the toolchain the
# CI's full correctness job uses (ci.yml: swift:6.4-noble) and put it on the
# PATH, so `swift build` and `swift test` work from the first command.
# Synchronous: the container is cached once this finishes, and later starts
# find the toolchain already there.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

"$CLAUDE_PROJECT_DIR/.github/scripts/install-swift-linux.sh" 6.4.0 /opt/swift
echo 'export PATH="/opt/swift/usr/bin:$PATH"' >> "$CLAUDE_ENV_FILE"
