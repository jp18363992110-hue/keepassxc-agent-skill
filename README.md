# 🔐 keepassxc-agent-skill

> An AI-agent skill for managing API keys, tokens and passwords with a local, keyfile-only KeePassXC vault — popup input, zero plaintext, secret never printed.
>
> 一个让 AI Agent 管理 API Key / Token / 密码的本地 KeePassXC 技能：弹窗录入、零明文落地、密钥永不外泄。

---

## ✨ Features / 功能特性

- **Credential Resolution Protocol / 鉴权需求自动决策** — when any task needs a password/key/token, the agent queries the vault FIRST; found → confirm with user; missing → offer to add via popup. / 任何任务需要凭据时，agent 先查库；命中→与用户确认；未命中→弹窗询问新增。
- **Get-or-input one-step flow / 一步闭环** — `kp.sh get-or-input <name>` returns the secret if it exists, otherwise opens a popup dialog (name prefilled) for manual entry. / 有则直接读出，无则弹窗录入。
- **Popup dialog / 原生弹窗录入** — tkinter dialog with masked input + show toggle, writes directly to the encrypted DB via CLI stdin; the value never touches disk, argv, or chat. / tkinter 弹窗，密钥经 stdin 直写加密库，不落盘、不进参数、不进对话。
- **Keyfile-only unlock / keyfile 免密解锁** — no master password needed, fully automatable. / 无需主密码，完全自动化。
- **Batch import / 批量导入** — `name=value` text files, CRLF-safe. / 支持 `名称=值` 文件批量导入，自动处理 CRLF 行尾。
- **Chinese entry names supported / 中文条目名** — fully tested. / 中文名条目实测可用。

## 📦 Installation / 安装

### Prerequisites / 依赖

- **KeePassXC** (>= 2.7) — `winget install KeePassXCTeam.KeePassXC`
- **Python 3** with tkinter (Windows: python.org installer / Miniconda both OK)
- Git Bash (or any bash shell) on Windows; works on macOS/Linux with adjusted paths

### Install the skill / 安装技能

```bash
# Option A: copy the folder into your skills directory
git clone https://github.com/jp18363992110-hue/keepassxc-agent-skill.git
cp -r keepassxc-agent-skill/keepassxc ~/.agents/skills/

# Option B: import the packaged .skill file into your skill registry
```

### Initialize the vault / 初始化保险库

```bash
mkdir -p ~/.secrets
head -c 64 /dev/urandom > ~/.secrets/keys.key     # keyfile (THE ONLY credential — back it up!)
/c/Program\ Files/KeePassXC/keepassxc-cli.exe db-create \
  --set-key-file ~/.secrets/keys.key ~/.secrets/secrets.kdbx
```

> ⚠️ The keyfile is the only way to unlock the database. **Lose the keyfile = data gone forever.** Back it up!
> ⚠️ keyfile 是唯一解锁凭证，丢失即数据永久丢失，务必备份！

Custom paths? Set env vars: `KPXC_CLI`, `KPXC_DB`, `KPXC_KEY` (and `KPXC_GUI`).

## 🚀 Usage / 使用

All operations go through `scripts/kp.sh`:

```bash
KP=keepassxc/scripts/kp.sh

# The main flow: get if exists, popup if missing
KEY=$(bash $KP get-or-input "OpenAI")

# Explicit read / 显式读取
KEY=$(bash $KP get "OpenAI")          # capture & inject, never print

# Store / 存储
bash $KP input "OpenAI"               # popup dialog (name prefilled)
bash $KP set "OpenAI" "$VALUE"        # non-interactive
bash $KP batch keys.txt               # batch: 名称=value per line, CRLF-safe
bash $KP batch keys.txt               # ⚠️ then destroy the plaintext file!

# Manage / 管理
bash $KP list                         # list entries
bash $KP search "deep"                # fuzzy search
bash $KP rm "OpenAI"                  # remove (recycle bin)
bash $KP check                        # health check
bash $KP open                         # open in KeePassXC GUI
```

## 🔒 Security model / 安全设计

- **Secret chain**: clipboard → dialog memory → CLI stdin → encrypted DB. Never chat, never argv, never disk. / 密钥链条：剪贴板 → 弹窗内存 → CLI stdin → 加密库。不进聊天/参数/磁盘。
- **Keyfile-only DB**: `--no-password -k <keyfile>` unlock (the #1 footgun — forgetting `--no-password` fails with "invalid credentials"). / 所有命令必须带 `--no-password -k keyfile`。
- **Agent guardrails embedded in SKILL.md**: confirm with user before injecting; destroy plaintext batch files after import; values via stdin only. / 技能内置护栏：注入前与用户确认、导入后销毁明文、值一律走 stdin。
- **`.gitignore`** in this repo blocks `*.kdbx` / `*.key` to prevent accidental vault commits. / 仓库 .gitignore 拦截密钥文件防止误提交。

## 🗂️ Repository layout / 仓库结构

```
keepassxc-agent-skill/
├── keepassxc/            # the skill (drop into ~/.agents/skills/)
│   ├── SKILL.md          # agent instructions + credential resolution protocol
│   ├── scripts/
│   │   ├── kp.sh         # CLI wrapper (get/set/input/get-or-input/batch/...)
│   │   └── kp-input.py   # tkinter popup dialog
│   └── references/
│       └── commands.md   # raw keepassxc-cli reference + troubleshooting
└── keepassxc.skill       # packaged distribution artifact
```

## 📄 License / 协议

[MIT](LICENSE) © 2026 jp18363992110-hue

---

*Built for the AI-agent era: credentials that agents can use without ever seeing. / 为 Agent 时代而生：凭据可被 AI 使用，却永不被 AI 看见。*
