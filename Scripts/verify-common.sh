#!/usr/bin/env bash

script_root() {
  cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd
}

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}
