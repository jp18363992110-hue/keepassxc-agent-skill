#!/usr/bin/env bash
# kp.sh — KeePassXC secret store helper (keyfile-only database)
#
# Usage:
#   kp.sh get <name>              Print secret value to stdout (use inside $( ) to capture)
#   kp.sh set <name> <value>      Store/replace a secret (value via argv)
#   kp.sh set <name> -            Store secret read from stdin
#   kp.sh add <name>              Add a new entry, value from stdin (fails if entry exists)
#   kp.sh list                    List all entry names
#   kp.sh search <term>           Search entries by name
#   kp.sh rm <name>               Remove entry (moves to recycle bin)
#   kp.sh batch <file>            Import name=value lines from file (CRLF safe)
#   kp.sh input [name]            Open popup dialog to enter a new secret (name prefilled)
#   kp.sh get-or-input <name>     Get secret; if missing, popup dialog prefilled, then re-get
#   kp.sh open                    Open database in KeePassXC GUI (manual keyfile pick)
#   kp.sh check                   Verify CLI/db/keyfile present and unlockable
#
# Env overrides: KPXC_CLI, KPXC_DB, KPXC_KEY
#
# CRITICAL: this database is keyfile-only. EVERY command must pass
# `--no-password -k "$KEY"` or the CLI will try a password and fail with
# "invalid credentials". This was the #1 footgun discovered during setup.

set -euo pipefail

# --- Path resolution: env override > PATH auto-detect > OS defaults ---
# (cross-platform: macOS/Linux installs keepassxc-cli on PATH via brew/apt)
if [ -n "${KPXC_CLI:-}" ]; then
  KPXC="$KPXC_CLI"
elif command -v keepassxc-cli >/dev/null 2>&1; then
  KPXC="$(command -v keepassxc-cli)"
else
  KPXC="/c/Program Files/KeePassXC/keepassxc-cli.exe"   # Windows default
fi

if [ -n "${KPXC_GUI:-}" ]; then
  GUI="$KPXC_GUI"
elif command -v keepassxc >/dev/null 2>&1; then
  GUI="$(command -v keepassxc)"
elif [ -x "/Applications/KeePassXC.app/Contents/MacOS/KeePassXC" ]; then
  GUI="/Applications/KeePassXC.app/Contents/MacOS/KeePassXC"
else
  GUI="/c/Program Files/KeePassXC/KeePassXC.exe"         # Windows default
fi

if [ -n "${KPXC_PYTHON:-}" ]; then
  PYTHON="$KPXC_PYTHON"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
else
  PYTHON=python
fi

DB="${KPXC_DB:-$HOME/.secrets/secrets.kdbx}"
KEY="${KPXC_KEY:-$HOME/.secrets/keys.key}"
UNLOCK=(--no-password -k "$KEY")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cmd="${1:-}"; shift || true

case "$cmd" in
  get)
    [ $# -eq 1 ] || { echo "usage: kp.sh get <name>" >&2; exit 2; }
    # `--` ends option parsing: entry names are untrusted data (may start with '-')
    # tr -d '\r': keepassxc-cli may emit CRLF on Windows; normalize so captures are clean
    "$KPXC" show "${UNLOCK[@]}" -a password "$DB" -- "$1" 2>/dev/null | tr -d '\r'
    ;;
  set)
    # set = add (if new) or edit (if exists)
    [ $# -ge 1 ] || { echo "usage: kp.sh set <name> [value|-]" >&2; exit 2; }
    name="$1"
    if [ $# -ge 2 ] && [ "$2" != "-" ]; then
      value="$2"
    else
      value="$(cat)"
    fi
    if "$KPXC" ls "${UNLOCK[@]}" "$DB" 2>/dev/null | tr -d '\r' | grep -qxF "$name"; then
      printf '%s\n' "$value" | "$KPXC" edit "${UNLOCK[@]}" -p "$DB" -- "$name" >/dev/null 2>&1 \
        && echo "updated: $name" || { echo "edit failed: $name" >&2; exit 1; }
    else
      printf '%s\n' "$value" | "$KPXC" add "${UNLOCK[@]}" -u "" -p "$DB" -- "$name" >/dev/null 2>&1 \
        && echo "added: $name" || { echo "add failed: $name" >&2; exit 1; }
    fi
    ;;
  add)
    [ $# -ge 1 ] || { echo "usage: kp.sh add <name>" >&2; exit 2; }
    printf '%s\n' "$(cat)" | "$KPXC" add "${UNLOCK[@]}" -u "" -p "$DB" -- "$1" >/dev/null 2>&1 \
      && echo "added: $1" || { echo "add failed (entry may already exist): $1" >&2; exit 1; }
    ;;
  list)
    # NOTE: keepassxc-cli ls emits CRLF on Windows — strip \r so output can be piped back into get/rm
    "$KPXC" ls "${UNLOCK[@]}" "$DB" 2>/dev/null | tr -d '\r'
    ;;
  search)
    [ $# -eq 1 ] || { echo "usage: kp.sh search <term>" >&2; exit 2; }
    "$KPXC" search "${UNLOCK[@]}" "$DB" "$1" 2>/dev/null | tr -d '\r'
    ;;
  rm)
    [ $# -eq 1 ] || { echo "usage: kp.sh rm <name>" >&2; exit 2; }
    "$KPXC" rm "${UNLOCK[@]}" "$DB" -- "$1" >/dev/null 2>&1 && echo "removed: $1"
    ;;
  batch)
    # Lines: name=value  (CRLF safe: strips trailing \r). Skips blank lines.
    [ $# -eq 1 ] || { echo "usage: kp.sh batch <file>" >&2; exit 2; }
    f="$1"; [ -f "$f" ] || { echo "file not found: $f" >&2; exit 1; }
    ok=0; fail=0
    while IFS= read -r line || [ -n "$line" ]; do
      [ -z "$line" ] && continue
      name="${line%%=*}"
      value="${line#*=}"
      value="${value%$'\r'}"
      if printf '%s\n' "$value" | "$KPXC" add "${UNLOCK[@]}" -u "" -p "$DB" -- "$name" >/dev/null 2>&1; then
        echo "OK: $name"; ok=$((ok+1))
      else
        echo "FAIL: $name"; fail=$((fail+1))
      fi
    done < "$f"
    echo "batch done: $ok ok, $fail failed"
    [ "$fail" -eq 0 ]
    ;;
  input)
    # Popup dialog; exit 0 = saved, 1 = canceled. Name optional (prefilled).
    [ $# -le 1 ] || { echo "usage: kp.sh input [name]" >&2; exit 2; }
    "$PYTHON" "$SCRIPT_DIR/kp-input.py" "${1:-}"
    ;;
  get-or-input)
    # Get secret; if missing, popup dialog prefilled with the name, then re-get.
    [ $# -eq 1 ] || { echo "usage: kp.sh get-or-input <name>" >&2; exit 2; }
    name="$1"
    # NOTE: `|| true` is required — set -e would abort silently when show fails on a missing entry
    value=$("$KPXC" show "${UNLOCK[@]}" -a password "$DB" -- "$name" 2>/dev/null | tr -d '\r' || true)
    if [ -n "$value" ]; then
      printf '%s' "$value"
    else
      echo "[提示] 条目 '$name' 不存在，请在弹出的窗口中录入" >&2
      if "$PYTHON" "$SCRIPT_DIR/kp-input.py" "$name"; then
        value=$("$KPXC" show "${UNLOCK[@]}" -a password "$DB" -- "$name" 2>/dev/null | tr -d '\r' || true)
        if [ -n "$value" ]; then
          echo "[完成] '$name' 已保存并读取成功" >&2
          printf '%s' "$value"
        else
          echo "[错误] 保存后读取失败，请检查数据库" >&2
          exit 1
        fi
      else
        echo "[取消] 未保存任何内容" >&2
        exit 1
      fi
    fi
    ;;
  open)
    "$GUI" "$DB" &
    ;;
  check)
    "$KPXC" --version
    [ -f "$DB" ] || { echo "DB missing: $DB" >&2; exit 1; }
    [ -f "$KEY" ] || { echo "KEY missing: $KEY" >&2; exit 1; }
    n=$("$KPXC" ls "${UNLOCK[@]}" "$DB" 2>/dev/null | grep -cv '^$' || true)
    echo "db: $DB ($n entries)"
    ;;
  *)
    echo "usage: kp.sh <get|set|add|list|search|rm|batch|input|get-or-input|open|check>" >&2
    exit 2
    ;;
esac
