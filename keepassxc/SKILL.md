---
name: keepassxc
description: Read, store, and inject API keys / tokens / secrets via the local KeePassXC keyfile-only database (~/.secrets/secrets.kdbx). Use when the user asks to save an API key, token, or password into the local vault; read a stored secret back (e.g. "use my 博查API key"); batch-import keys from a name=value file; inject secrets into a command's environment without printing them; or whenever any task requires a password / key / token / auth credential — query the vault FIRST, confirm matches with the user before use, and offer to add missing credentials via popup dialog.
---

# KeePassXC local secret store

Manage the user's local KeePassXC vault for API keys, tokens, and passwords.

## Credential Resolution Protocol (agent behavior — follow for ANY auth need)

Whenever the task needs a password, API key, token, or any auth credential:

1. **Detect** — recognize the need: user mentions 密码 / key / 密钥 / 鉴权 / token / Authorization, or the task involves calling an API / logging in / a service that needs a credential.
2. **Query the vault FIRST** — never ask the user to hand over the secret before checking the vault:
   - Exact name known: `kp.sh get "<name>"`
   - Fuzzy or partial name: `kp.sh search <term>` (lists candidate entries)
3. **Found → confirm with the user** — show the matched entry name(s) and confirm before using: e.g. "在密码库中找到 XX，用这个吗？" If multiple candidates match, list them and let the user pick. Never inject without confirmation.
4. **Not found → offer to add** — say it's not in the vault and ask whether to create it: "库中没有 XX，需要新增吗？"
   - Yes → `kp.sh input "<name>"` (popup dialog, name prefilled; add-or-update handled automatically)
   - No → continue with whatever the user provides, or report the credential is unavailable.
5. **Use** — capture into a variable, inject into the command env, never print.

## Layout

- Database: `~/.secrets/secrets.kdbx` — **keyfile-only, no password**
- Keyfile: `~/.secrets/keys.key` — the *only* unlock credential. Never lose it.
- CLI: `C:\Program Files\KeePassXC\keepassxc-cli.exe` (Git Bash path `/c/Program Files/...`)
- Helper: `scripts/kp.sh` wraps all operations. **Use it instead of raw CLI calls.**

## Workflow

1. **Get-or-store in one step** (the primary flow): `KEY=$(bash scripts/kp.sh get-or-input "条目名")`
   - Entry exists → secret returned immediately, no dialog, zero friction.
   - Entry missing → a popup dialog opens (name prefilled); the user pastes the value and clicks 保存; the dialog writes directly to the DB (value travels clipboard → dialog memory → CLI stdin → encrypted DB, never to disk/argv/chat); the script then re-reads and confirms.
   - Canceled → exits 1, nothing stored.
2. **Check** the store: `bash scripts/kp.sh check` (CLI + db + keyfile + unlock).
3. **Read** a secret explicitly: `KEY=$(bash scripts/kp.sh get "条目名")` — inject into the command's env, never print.
4. **Store** a secret:
   - Interactive: `bash scripts/kp.sh input [名称]` — popup dialog.
   - Single (non-interactive): `bash scripts/kp.sh set "条目名" "$VALUE"` (or pipe value via stdin with `-`).
   - Batch import from file: `bash scripts/kp.sh batch <file>` — file lines `名称=value`, CRLF-safe; **destroy the plaintext file afterwards** (overwrite with random bytes, then delete).
5. **List/search**: `kp.sh list`, `kp.sh search <term>`.
6. **Remove**: `kp.sh rm "条目名"` (goes to recycle bin; delete the recycle bin group `回收站` with `keepassxc-cli rmdir --no-password -k <keyfile> <db> 回收站` when cleaning up).

## Guardrails (non-negotiable)

- **Always unlock with `--no-password -k <keyfile>`** — the DB has no password. Omitting `--no-password` fails with "invalid credentials" (the #1 footgun).
- **Never print secrets** to chat, logs, or code. Capture into a variable and consume within the same shell command.
- **Pass values via stdin**, never as command-line arguments (argv leaks into process listings).
- The popup dialog (`kp-input.py`) is the preferred manual-entry path — the value never touches disk, argv, or chat. It writes directly via CLI stdin.
- `kp.sh` uses `set -euo pipefail`: when checking whether an entry exists, always append `|| true` to the `show`/`ls` command substitution or the script will silently abort.
- Chinese entry names work fine — quote them in commands.
- Batch files written by Notepad have CRLF endings; `kp.sh batch` strips `\r` automatically.
- If a secret needs to appear in a config file, prefer templating over writing the raw value; if unavoidable, delete the file after use.
- GUI access: `kp.sh open` opens the vault; user picks the keyfile manually.

## Details

- Command reference: see `references/commands.md` for raw `keepassxc-cli` usage and troubleshooting.
