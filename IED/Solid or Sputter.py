#!/usr/bin/env python3
# solid_or_sputter.py

import os
import sys
import shutil
from pathlib import Path
from functools import partial

try:
    from tkinterdnd2 import DND_FILES, TkinterDnD
    DND_AVAILABLE = True
except Exception:
    DND_AVAILABLE = False

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from PIL import Image, ImageTk

APP_TITLE = "Solid or Sputter"
INSTRUCTIONS = "Welcome! Drop it like it's hot…\nDrop a folder here or click Open Folder."

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tif", ".tiff", ".webp", ".jfif"}

# ⬇️ Added "Flag" here
SUBFOLDERS = ["Solid", "Sputter", "Garbage", "Flag"]

CANVAS_W, CANVAS_H = 1000, 700

def natural_key(p: Path):
    import re
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", p.stem)]

class SolidOrSputterApp:
    def __init__(self, root):
        self.root = root
        self.root.title(APP_TITLE)
        self.root.geometry("1100x880")
        self.root.minsize(900, 720)

        self.folder = None
        self.images = []
        self.index = 0
        self.tk_img = None

        header = ttk.Frame(root, padding=(10, 8))
        header.pack(fill="x")
        self.title_lbl = ttk.Label(header, text=APP_TITLE, font=("Segoe UI", 16, "bold"))
        self.title_lbl.pack(side="left")
        self.open_btn = ttk.Button(header, text="Open Folder", command=self.open_folder)
        self.open_btn.pack(side="right", padx=(6, 0))
        self.reset_btn = ttk.Button(header, text="Start Over", command=self.reset, state="disabled")
        self.reset_btn.pack(side="right", padx=(6, 6))

        mid = ttk.Frame(root, padding=(10, 0))
        mid.pack(fill="both", expand=True)

        self.drop = tk.Label(
            mid,
            text=INSTRUCTIONS + ("\n(Drag-and-drop available)" if DND_AVAILABLE else "\n(Install 'tkinterdnd2' to enable drag-and-drop)"),
            relief="ridge", borderwidth=2, anchor="center", justify="center",
            fg="#333", font=("Segoe UI", 12),
        )
        self.drop.pack(fill="x", pady=(4, 8))
        self.drop.configure(height=4)
        if DND_AVAILABLE:
            self.drop.drop_target_register(DND_FILES)
            self.drop.dnd_bind("<<Drop>>", self.on_drop)

        self.canvas = tk.Canvas(mid, width=CANVAS_W, height=CANVAS_H, bg="#111", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)

        foot = ttk.Frame(root, padding=(10, 8))
        foot.pack(fill="x")
        self.progress = ttk.Progressbar(foot, orient="horizontal", mode="determinate")
        self.progress.pack(fill="x", side="left", expand=True, padx=(0, 12))
        self.count_lbl = ttk.Label(foot, text="0 / 0", width=10, anchor="e")
        self.count_lbl.pack(side="left")

        # ⬇️ Added Flag button
        btns = ttk.Frame(root, padding=(10, 0))
        btns.pack(fill="x")
        self.btn_solid   = ttk.Button(btns, text="Solid [1]",   command=partial(self.sort_current, "Solid"),   state="disabled")
        self.btn_sputter = ttk.Button(btns, text="Sputter [2]", command=partial(self.sort_current, "Sputter"), state="disabled")
        self.btn_garbage = ttk.Button(btns, text="Garbage [3]", command=partial(self.sort_current, "Garbage"), state="disabled")
        self.btn_flag    = ttk.Button(btns, text="Flag [4 / F]",command=partial(self.sort_current, "Flag"),    state="disabled")
        self.btn_solid.pack(side="left", padx=(0, 6))
        self.btn_sputter.pack(side="left", padx=6)
        self.btn_garbage.pack(side="left", padx=6)
        self.btn_flag.pack(side="left", padx=6)
        self.btn_skip = ttk.Button(btns, text="Skip [Space]", command=self.skip_current, state="disabled")
        self.btn_skip.pack(side="left", padx=6)

        # Shortcuts (⬇️ added 4/F for Flag)
        self.root.bind("<KeyPress-1>", lambda e: self.sort_current("Solid"))
        self.root.bind("<KeyPress-2>", lambda e: self.sort_current("Sputter"))
        self.root.bind("<KeyPress-3>", lambda e: self.sort_current("Garbage"))
        self.root.bind("<KeyPress-4>", lambda e: self.sort_current("Flag"))
        self.root.bind("<KeyPress-f>", lambda e: self.sort_current("Flag"))
        self.root.bind("<KeyPress-F>", lambda e: self.sort_current("Flag"))
        self.root.bind("<space>",     lambda e: self.skip_current())
        self.root.bind("<Left>",      lambda e: self.prev_image())
        self.root.bind("<Right>",     lambda e: self.next_image())

        self.status("Pick a folder to begin.")

    # ---- folder handling ----
    def on_drop(self, event):
        raw = event.data.strip()
        if raw.startswith("{") and raw.endswith("}"):
            raw = raw[1:-1]
        p = Path(raw)
        if p.exists():
            self.load_folder(p if p.is_dir() else p.parent)
        else:
            messagebox.showerror(APP_TITLE, "Dropped path not found.")

    def open_folder(self):
        sel = filedialog.askdirectory(title="Choose a folder of images")
        if sel:
            self.load_folder(Path(sel))

    def load_folder(self, folder: Path):
        self.folder = folder
        sub_names = set(SUBFOLDERS)
        paths = []
        for child in folder.iterdir():
            if child.is_dir() and child.name in sub_names:
                continue
            if child.is_file() and child.suffix.lower() in IMAGE_EXTS:
                paths.append(child)
        paths.sort(key=natural_key)
        self.images = paths
        self.index = 0

        # Ensure all subfolders exist (⬇️ includes Flag)
        for name in SUBFOLDERS:
            (folder / name).mkdir(exist_ok=True)

        total = len(self.images)
        if total == 0:
            self.enable_controls(False)
            self.progress.config(value=0, maximum=1)
            self.count_lbl.config(text="0 / 0")
            self.canvas_delete_all()
            self.status("No images found in this folder.")
            return

        self.enable_controls(True)
        self.progress.config(value=0, maximum=total)
        self.count_lbl.config(text=f"0 / {total}")
        self.drop.config(text=f"Folder: {folder}\nDrag another folder or click Open Folder to switch.")
        self.reset_btn.config(state="normal")
        self.show_current()

    def enable_controls(self, enable: bool):
        state = "normal" if enable else "disabled"
        for b in (self.btn_solid, self.btn_sputter, self.btn_garbage, self.btn_flag, self.btn_skip):
            b.config(state=state)

    # ---- navigation & labeling ----
    def show_current(self):
        self.canvas_delete_all()
        if not self.images or self.index >= len(self.images):
            self.finish()
            return
        img_path = self.images[self.index]
        self.status(f"Viewing {img_path.name}")
        try:
            img = Image.open(img_path).convert("RGB")
        except Exception as e:
            self.status(f"Failed to open {img_path.name}: {e}")
            self.next_image()
            return

        w, h = img.size
        scale = min(CANVAS_W / max(1, w), CANVAS_H / max(1, h))
        new_w, new_h = max(1, int(w * scale)), max(1, int(h * scale))
        img = img.resize((new_w, new_h), Image.LANCZOS)

        self.tk_img = ImageTk.PhotoImage(img)
        x = (CANVAS_W - new_w) // 2
        y = (CANVAS_H - new_h) // 2
        self.canvas.create_image(x, y, anchor="nw", image=self.tk_img)
        self.canvas.create_rectangle(0, CANVAS_H - 30, CANVAS_W, CANVAS_H, fill="#000", stipple="gray25", outline="")
        self.canvas.create_text(10, CANVAS_H - 15, text=img_path.name, anchor="w", fill="#fff", font=("Segoe UI", 10))
        self.count_lbl.config(text=f"{self.index} / {len(self.images)}")

    def sort_current(self, label: str):
        if not self.images or self.index >= len(self.images):
            return
        img_path = self.images[self.index]
        dest_dir = self.folder / label
        dest = self._unique_dest(dest_dir / img_path.name)
        try:
            shutil.move(str(img_path), str(dest))
        except Exception as e:
            messagebox.showerror(APP_TITLE, f"Could not move file:\n{e}")
            return
        self.index += 1
        self.progress.step(1)
        self.count_lbl.config(text=f"{min(self.index, len(self.images))} / {len(self.images)}")
        self.show_current()

    def skip_current(self):
        if not self.images or self.index >= len(self.images):
            return
        self.index += 1
        self.progress.step(1)
        self.count_lbl.config(text=f"{min(self.index, len(self.images))} / {len(self.images)}")
        self.show_current()

    def prev_image(self):
        if not self.images:
            return
        self.index = max(0, self.index - 1)
        self.show_current()

    def next_image(self):
        if not self.images:
            return
        self.index = min(len(self.images), self.index + 1)
        self.show_current()

    def finish(self):
        self.enable_controls(False)
        self.canvas_delete_all()
        self.progress.config(value=self.progress["maximum"])
        self.count_lbl.config(text=f"{self.progress['maximum']} / {self.progress['maximum']}")
        self.status("All done! You can open another folder.")
        self.drop.config(text="Sorted! Drop another folder or click Open Folder.")

    def reset(self):
        self.folder = None
        self.images = []
        self.index = 0
        self.progress.config(value=0, maximum=1)
        self.count_lbl.config(text="0 / 0")
        self.drop.config(text=INSTRUCTIONS + ("\n(Drag-and-drop available)" if DND_AVAILABLE else "\n(Install 'tkinterdnd2' to enable drag-and-drop)"))
        self.enable_controls(False)
        self.reset_btn.config(state="disabled")
        self.canvas_delete_all()
        self.status("Pick a folder to begin.")

    # ---- helpers ----
    def canvas_delete_all(self):
        self.canvas.delete("all")
        self.canvas.config(width=CANVAS_W, height=CANVAS_H)

    def status(self, text: str):
        self.root.title(f"{APP_TITLE} — {text}")

    def _unique_dest(self, candidate: Path) -> Path:
        if not candidate.exists():
            return candidate
        stem, suffix = candidate.stem, candidate.suffix
        i = 1
        while True:
            trial = candidate.with_name(f"{stem} ({i}){suffix}")
            if not trial.exists():
                return trial
            i += 1


def main():
    if DND_AVAILABLE:
        root = TkinterDnD.Tk()
    else:
        root = tk.Tk()
    try:
        style = ttk.Style(root)
        if sys.platform.startswith("win"):
            style.theme_use("vista")
    except Exception:
        pass
    app = SolidOrSputterApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
