# keepassxc-cli 命令参考与排障

## 弹窗录入（推荐的人机交互路径）

```bash
# 一条命令闭环：有则直接读出，无则弹窗录入（名称预填）→ 保存 → 读回
KEY=$(bash scripts/kp.sh get-or-input "条目名")

# 仅弹窗录入（不查）
bash scripts/kp.sh input "条目名"
```

- 弹窗实现：`scripts/kp-input.py`（tkinter，Python 3 + tkinter 8.6 已确认可用）
- 保存时值经 stdin 直接写入数据库，**不产生中间明文文件**、不进 argv
- 退出码：0 = 已保存，1 = 取消/失败
- 无界面测试模式（与弹窗共用同一保存逻辑）：`printf 'value\n' | python kp-input.py --save "名称" "备注"`
- `kp-input.py` 同样支持 `KPXC_CLI` / `KPXC_DB` / `KPXC_KEY` 环境变量覆盖

## 关键前提

数据库是 **keyfile-only**（无密码）。所有命令必须带：

```bash
--no-password -k ~/.secrets/keys.key
```

缺失 `--no-password` 时 CLI 会提示「输入密码以解锁」并报 `invalid credentials`——这是最常见的失败原因。GUI 里选中数据库时凭证方式也要选 **Key File**。

## 常用命令（原始 CLI）

```bash
KPXC="/c/Program Files/KeePassXC/keepassxc-cli.exe"
DB=~/.secrets/secrets.kdbx
KEY=~/.secrets/keys.key
UNLOCK=(--no-password -k "$KEY")

# 列出条目
"$KPXC" ls "${UNLOCK[@]}" "$DB"

# 读取密码字段（-a password 只输出值本身，便于捕获）
"$KPXC" show "${UNLOCK[@]}" -a password "$DB" "条目名"

# 新增条目（密码经 stdin 传入，勿用命令行参数）
printf '%s\n' "$VALUE" | "$KPXC" add "${UNLOCK[@]}" -u "" -p "$DB" "条目名"

# 更新条目（同样 stdin）
printf '%s\n' "$VALUE" | "$KPXC" edit "${UNLOCK[@]}" -p "$DB" "条目名"

# 搜索
"$KPXC" search "${UNLOCK[@]}" "$DB" "关键词"

# 删除（进回收站）与清空回收站群组
"$KPXC" rm "${UNLOCK[@]}" "$DB" "条目名"
"$KPXC" rmdir "${UNLOCK[@]}" "$DB" "回收站"

# 数据库信息
"$KPXC" db-info "${UNLOCK[@]}" "$DB"
```

## 环境变量覆盖

`kp.sh` 支持 `KPXC_CLI` / `KPXC_DB` / `KPXC_KEY` 覆盖默认路径（测试、多数据库场景）。

## 批量导入约定

`kp.sh batch <file>` 要求文件每行 `名称=value`：

- 名称中英文均可，建议英文以便命令行引用（中文需加引号）
- CRLF 行尾（Notepad 默认）会被自动剥离
- 导入完成后必须销毁明文文件：
  ```bash
  head -c 65536 /dev/urandom > file; rm -f file   # 覆盖后删除（无 shred 时的替代）
  # 有 shred 则： shred -u -n 3 file
  ```

## 排障记录（实测）

| 症状 | 原因 | 解法 |
|---|---|---|
| 提示输入密码且解锁失败 | keyfile-only 库但漏了 `--no-password` | 加 `--no-password` |
| `db-create` 后 CLI 打不开 | `db-create` 只带 `--set-key-file` 时创建的库 CLI 无法解锁（实测 bug 或行为差异） | 用 GUI 建库，或用密码+keyfile 建库后再调整；优先用现有库 |
| `-p` 传密码失败 | 创建数据库时密码提示**两次**（输入+确认） | `printf 'pwd\npwd\n'` 两行 |
| 批导入后长度多 1 | CRLF 残留 `\r` | 用 `kp.sh batch`（已处理） |
| 脚本静默退出、无任何输出 | `set -e` 遇到 `show`/`ls` 查不到条目时退出 | 命令替换处加 `|| true`（`kp.sh` 已内置，自定义脚本时注意） |
| 弹窗不出现，`python kp-input.py` 直接退出 | 子进程调用时位置参数顺序错：`add [选项] 数据库 条目` | 先命令+选项，再数据库，最后条目（`kp-input.py` 已修正） |
| `list`/`search` 输出带 `\r`（`^M`），管道回 `get` 全部失败 | Windows 下 `keepassxc-cli ls` 输出 CRLF | `kp.sh list/search` 已内置 `tr -d '\r'`（v1.2.1） |

## 备份

- 数据库和 keyfile 是**一体**的：丢 keyfile = 数据永久不可读
- 建议定期把 `~/.secrets/` 两个文件复制到安全位置（U 盘、私有 Git 仓库）
- 数据库是加密的，备份本身可明文存放；keyfile 同样可随库备份（它本身就是密钥）
