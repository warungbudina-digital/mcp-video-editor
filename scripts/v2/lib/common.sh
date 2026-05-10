#!/bin/bash

log_section() {
  echo ""
  echo "==============================="
  echo "$1"
  echo "==============================="
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "❌ Command wajib tidak ditemukan: $1"
    exit 1
  }
}

ensure_file() {
  [ -f "$1" ] || {
    echo "❌ File wajib tidak ditemukan: $1"
    exit 1
  }
}

ensure_env() {
  [ -n "${!1:-}" ] || {
    echo "❌ Env wajib belum di-set: $1"
    exit 1
  }
}

ensure_dir() {
  mkdir -p "$1"
}
