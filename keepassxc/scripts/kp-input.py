#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""KeePassXC keyfile-only DB: popup input dialog for storing secrets.

Usage:
  kp-input.py [entry_name]    open dialog (name prefilled)
  kp-input.py --save <name>   headless save (value from stdin, notes from arg 2) — for testing

Exit codes: 0 = saved, 1 = canceled / failed.
Env overrides (same as kp.sh): KPXC_CLI, KPXC_DB, KPXC_KEY.
Security: the value travels clipboard -> dialog memory -> CLI stdin -> encrypted DB.
It is never written to disk, argv, chat, or logs.
"""

import os
import subprocess
import sys
import tkinter as tk
from tkinter import messagebox, ttk

APP_TITLE = "存储密钥到 KeePassXC"


def paths():
    home = os.path.expanduser("~")
    return {
        "cli": os.environ.get("KPXC_CLI", r"C:\Program Files\KeePassXC\keepassxc-cli.exe"),
        "db": os.environ.get("KPXC_DB", os.path.join(home, ".secrets", "secrets.kdbx")),
        "key": os.environ.get("KPXC_KEY", os.path.join(home, ".secrets", "keys.key")),
    }


UNLOCK = ["--no-password", "-k"]


def run_cli(p, *args, input_text=None):
    """Run keepassxc-cli; args = subcommand + flags + db + entry (positional order).
    Value goes via stdin only, never argv."""
    cmd = [p["cli"], *args]
    data = (input_text + "\n").encode("utf-8") if input_text is not None else None
    r = subprocess.run(cmd, input=data, capture_output=True)
    return r


def entry_names(p):
    r = run_cli(p, "ls", *UNLOCK, p["key"], p["db"], "--")
    return r.stdout.decode("utf-8", "replace").splitlines()


def save_entry(p, name, value, notes=""):
    """Add or update an entry. Returns (ok, detail).
    `--` ends option parsing: entry names are untrusted data (may start with '-')."""
    value = value.rstrip("\r\n")
    names = entry_names(p)
    cmd = "edit" if name in names else "add"
    if cmd == "add":
        r = run_cli(p, "add", *UNLOCK, p["key"], "-u", "", "-p", "--notes", notes, p["db"], "--", name,
                    input_text=value)
    else:
        r = run_cli(p, "edit", *UNLOCK, p["key"], "-p", "--notes", notes, p["db"], "--", name,
                    input_text=value)
    if r.returncode == 0:
        return True, ("已更新" if cmd == "edit" else "已新增") + f": {name}"
    detail = r.stderr.decode("utf-8", "replace").strip().splitlines()
    return False, (detail[-1] if detail else f"keepassxc-cli 退出码 {r.returncode}")


def headless_save(name, notes=""):
    p = paths()
    value = sys.stdin.read()
    ok, detail = save_entry(p, name, value, notes)
    print(detail)
    return 0 if ok else 1


class InputDialog:
    def __init__(self, prefill=""):
        self.root = tk.Tk()
        self.root.title(APP_TITLE)
        self.root.resizable(False, False)
        self.root.attributes("-topmost", True)

        frm = ttk.Frame(self.root, padding=16)
        frm.grid()

        ttk.Label(frm, text="条目名称:").grid(row=0, column=0, sticky="e", pady=4)
        self.name_var = tk.StringVar(value=prefill)
        ttk.Entry(frm, textvariable=self.name_var, width=36).grid(row=0, column=1, columnspan=2, pady=4)

        ttk.Label(frm, text="密钥值:").grid(row=1, column=0, sticky="e", pady=4)
        self.value_var = tk.StringVar()
        self.value_entry = ttk.Entry(frm, textvariable=self.value_var, width=28, show="•")
        self.value_entry.grid(row=1, column=1, pady=4, sticky="we")
        self.show_btn = ttk.Button(frm, text="显示", width=6, command=self.toggle_show)
        self.show_btn.grid(row=1, column=2, padx=(4, 0), pady=4)
        self._hidden = True

        ttk.Label(frm, text="备注:").grid(row=2, column=0, sticky="e", pady=4)
        self.notes_var = tk.StringVar()
        ttk.Entry(frm, textvariable=self.notes_var, width=36).grid(row=2, column=1, columnspan=2, pady=4)

        btns = ttk.Frame(frm)
        btns.grid(row=3, column=0, columnspan=3, pady=(12, 0), sticky="e")
        ttk.Button(btns, text="取消", command=self.on_cancel).pack(side="left", padx=4)
        ttk.Button(btns, text="💾 保存", command=self.on_save).pack(side="left")

        self.value_entry.bind("<Return>", lambda _e: self.on_save())
        self.root.bind("<Escape>", lambda _e: self.on_cancel())

        self.root.update_idletasks()
        w, h = self.root.winfo_width(), self.root.winfo_height()
        x = (self.root.winfo_screenwidth() - w) // 2
        y = (self.root.winfo_screenheight() - h) // 3
        self.root.geometry(f"+{x}+{y}")
        self.value_entry.focus_set()

    def toggle_show(self):
        self._hidden = not self._hidden
        self.value_entry.config(show="•" if self._hidden else "")
        self.show_btn.config(text="隐藏" if not self._hidden else "显示")

    def on_cancel(self):
        self.root.destroy()
        sys.exit(1)

    def on_save(self):
        name = self.name_var.get().strip()
        value = self.value_var.get()
        if not name:
            messagebox.showwarning(APP_TITLE, "条目名称不能为空", parent=self.root)
            return
        if not value:
            messagebox.showwarning(APP_TITLE, "密钥值不能为空", parent=self.root)
            return
        ok, detail = save_entry(paths(), name, value, self.notes_var.get().strip())
        if ok:
            messagebox.showinfo(APP_TITLE, detail + "\n已写入加密数据库 ✔", parent=self.root)
            self.root.destroy()
            sys.exit(0)
        messagebox.showerror(APP_TITLE, "保存失败：\n" + detail, parent=self.root)

    def run(self):
        self.root.mainloop()
        return 1  # window closed without action


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--save":
        name = sys.argv[2] if len(sys.argv) >= 3 else ""
        notes = sys.argv[3] if len(sys.argv) >= 4 else ""
        sys.exit(headless_save(name, notes))
    prefill = sys.argv[1] if len(sys.argv) >= 2 else ""
    InputDialog(prefill).run()
