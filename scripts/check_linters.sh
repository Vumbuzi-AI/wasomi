#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v mix >/dev/null 2>&1; then
  echo "mix is required, but it was not found in PATH." >&2
  exit 1
fi

echo "==> Installing missing Mix dependencies"
mix deps.get

echo "==> Checking formatting"
mix format --check-formatted

echo "==> Running Credo"
mix credo --strict

echo "==> Running tests"
mix test

echo "==> Checks passed"
