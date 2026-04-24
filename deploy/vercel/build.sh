#!/bin/bash
# Wrapper for local/docs — canonical script is vercel-build.sh at repo root.
set -e
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
exec bash vercel-build.sh
