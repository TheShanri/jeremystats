import os
import csv
import re
import tkinter as tk
from tkinter import ttk
from PIL import Image, ImageTk
from RegionFilter import RegionFilterDialog

# ---------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------
IMG_DIR = r"D:\HOF DATA\ACTIVE DATA\PYTHON_UI_DATA\Combo_Events"
STATS_DIR = r"D:\HOF DATA\ACTIVE DATA\PYTHON_UI_DATA\PRE GENERATED STATS"
LOG_FILE = os.path.join(IMG_DIR, "Ultra_Master_Log.csv")

ORDERED_REGIONS = [
    'LeftPOR', 'RightPOR', 'LeftPER', 'RightPER',
    'LeftOFC', 'RightOFC', 'LeftACC', 'RightACC',
    'LeftDHC', 'RightDHC', 'LeftRSC', 'RightRSC'
]

ORDERED_EVENTS = ['Click_Noise', 'HighTone_LowTone']
ORDERED_FILTERS = ['Raw', 'Delta', 'Theta', 'Gamma']

EVENT_COLORS = {
    'Click_Noise': "#8400ff",       
    'HighTone_LowTone': "#00bd39",  
    'Click': '#1f77b4',        
    'Noise': '#ff7f0e',        
    'HighTone': '#2ca02c',     
    'LowTone': '#d62728',      
    'MagPoke': '#8c564b'       
}

# ---------------------------------------------------------------------
# HELPER FUNCTIONS
# ---------------------------------------------------------------------
def sort_with_preferred(items, preferred):
    items = list(items)
    pref = [x for x in preferred if x in items]
    rest = sorted([x for x in items if x not in preferred])
    return pref + rest

def ms_key(mouse, session):
    return f"{mouse} | {session}" if session else f"{mouse} | (no-session)"

def fl_key(filt, limits):
    return f"{filt} {limits}".strip()

def clean_matlab_region(matlab_str):
    # Converts "Left_POR_Ch01" strictly to "LeftPOR" for filtering logic
    parts = matlab_str.rsplit('_', 1)[0]
    return parts.replace('_', '')

# ---------------------------------------------------------------------
# UI APP
# ---------------------------------------------------------------------
class ComboMaster:
    def __init__(self, root):
        self.root = root
        self.root.title("NeuroScope Combo Viewer - Timeline & Stats Edition")
        try:
            self.root.state("zoomed")
        except tk.TclError:
            self.root.geometry("1400x900")

        # Database
        self.records = []
        self.by_key = {}  
        self.eidx_by_panelkey = {}  
        self.event_time_lookup = {} 
        self.session_timeline_data = {} 
        self.stats_db = {}

        # The State Master for the Filter Module
        self.active_stats_regions = set(ORDERED_REGIONS)

        # Dropdown options
        self.ms_pairs = []
        self.ms_labels = []
        self.ms_label_to_pair = {}

        self.filter_limits = []
        self.filter_limits_labels = []
        self.fl_label_to_pair = {}

        self.windows = []
        self.event_indices = []

        # Selections
        self.sel_ms = tk.StringVar()
        self.sel_fl = tk.StringVar()
        self.sel_window = tk.StringVar()
        self.sel_combo_type = tk.StringVar(value=ORDERED_EVENTS[0])
        self.sel_eidx = tk.StringVar(value="(any)")

        self.panel_eidx_pos = {}

        # UI References
        self.panels = []
        self._resize_job = None
        self._img_cache = {}
        self._img_cache_max = 250

        # Boot Sequence
        self.scan_database()
        self.scan_stats_database()
        self.setup_ui()
        self.bind_keys()

    # ---------------- Databases ----------------
    def scan_database(self):
        if not os.path.exists(LOG_FILE):
            print(f"[CRITICAL] Master log not found at: {LOG_FILE}")
            return

        ms_pairs = set()
        fl_pairs = set()
        wins = set()
        eidx_set = set()

        by_key = {}
        eidx_time_map = {} 
        records = []
        missing_images = 0

        with open(LOG_FILE, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    mouse = row['Mouse'].strip()
                    session = row['Session'].strip()
                    win = f"x{row['WinSec'].strip()}"
                    event = row['Event'].strip()
                    event_index = row['EventIdx'].strip()
                    img_id = row['ImageID'].strip()
                    
                    try:
                        ev_time = float(row.get('EventTimeSec', -1))
                    except (ValueError, TypeError):
                        ev_time = -1.0
                    
                    self.event_time_lookup[(mouse, session, event, event_index)] = ev_time

                    region = row['Region'].replace(" ", "").strip()
                    filt = "Raw"
                    limits = "l0h0"
                    path = os.path.join(IMG_DIR, f"{img_id}.png")

                    if not os.path.exists(path):
                        missing_images += 1
                        continue

                    rec = {
                        "mouse": mouse, "session": session, "win": win,
                        "filter": filt, "limits": limits, "event": event,
                        "event_index": event_index, "region": region,
                        "filename": f"{img_id}.png", "path": path,
                    }

                    records.append(rec)
                    ms_pairs.add((mouse, session))
                    fl_pairs.add((filt, limits))
                    wins.add(win)
                    eidx_set.add(event_index)

                    key = (mouse, session, win, filt, limits, event, region, event_index)
                    by_key[key] = path

                    panelkey = (mouse, session, win, filt, limits, event, region)
                    eidx_time_map.setdefault(panelkey, set()).add((event_index, ev_time))

                except KeyError as e:
                    print(f"[CRITICAL] Missing expected column in CSV: {e}")
                    return

        for k, v in eidx_time_map.items():
            sorted_v = sorted(list(v), key=lambda x: (x[1] if x[1] >= 0 else float('inf'), int(x[0]) if x[0].isdigit() else 0))
            self.eidx_by_panelkey[k] = [x[0] for x in sorted_v]

        for (mouse, sess, event, eidx), time_sec in self.event_time_lookup.items():
            if time_sec >= 0:
                key = (mouse, sess)
                if key not in self.session_timeline_data:
                    self.session_timeline_data[key] = []
                entry = (time_sec, event, eidx)
                if entry not in self.session_timeline_data[key]:
                    self.session_timeline_data[key].append(entry)

        for k in self.session_timeline_data:
            self.session_timeline_data[k].sort(key=lambda x: x[0])

        self.records = records
        self.by_key = by_key

        ms_pairs_sorted = sorted(list(ms_pairs), key=lambda x: (x[0], x[1]))
        self.ms_pairs = ms_pairs_sorted
        self.ms_labels = [ms_key(m, s) for m, s in ms_pairs_sorted]
        self.ms_label_to_pair = {ms_key(m, s): (m, s) for m, s in ms_pairs_sorted}

        fl_pairs_sorted = sorted(list(fl_pairs), key=lambda p: (ORDERED_FILTERS.index(p[0]) if p[0] in ORDERED_FILTERS else 999, p[1]))
        self.filter_limits = fl_pairs_sorted
        self.filter_limits_labels = [fl_key(f, lim) for f, lim in fl_pairs_sorted]
        self.fl_label_to_pair = {fl_key(f, lim): (f, lim) for f, lim in fl_pairs_sorted}

        self.windows = sorted(list(wins), key=lambda x: int(x[1:]) if x[1:].isdigit() else x)
        self.event_indices = sorted(list(eidx_set), key=lambda x: int(x) if x.isdigit() else x)

        if self.ms_labels:
            self.sel_ms.set(self.ms_labels[0])
        if self.windows:
            self.sel_window.set(self.windows[0])
        if self.filter_limits_labels:
            self.sel_fl.set(self.filter_limits_labels[0])

        # Force the first available trial index on boot
        if self.event_indices:
            self.sel_eidx.set(self.event_indices[0])
        else:
            self.sel_eidx.set("(any)")

        print(f"[DB] Indexed {len(self.records)} raw images from Master Log.")
        if missing_images > 0:
            print(f"[WARNING] {missing_images} files listed in CSV were not found on disk.")

    def scan_stats_database(self):
        if not os.path.exists(STATS_DIR):
            print(f"[WARNING] Dynamic Stats directory not found at: {STATS_DIR}")
            return
            
        pattern = re.compile(r"^(.*?)_(Click_Noise|HighTone_LowTone)_Trial(\d+)_(.*)_vs_(.*?)\.png$")
        
        count = 0
        for root, _, files in os.walk(STATS_DIR):
            for file in files:
                match = pattern.match(file)
                if match:
                    session_id = match.group(1) 
                    event_type = match.group(2)
                    trial_num = str(int(match.group(3))) 
                    ch1 = match.group(4)
                    ch2 = match.group(5)
                    
                    parts = session_id.split('_', 1)
                    if len(parts) == 2:
                        mouse, sess = parts[0], parts[1]
                        key = (mouse, sess, event_type, trial_num)
                        
                        if key not in self.stats_db:
                            self.stats_db[key] = []
                        self.stats_db[key].append((ch1, ch2, os.path.join(root, file)))
                        count += 1
                        
        print(f"[DB] Indexed {count} dynamic connectivity heatmaps.")

    # ---------------- UI Setup ----------------
    def setup_ui(self):
        # 1. TOP CONTROLS
        top = tk.Frame(self.root, bg="#ddd", height=56)
        top.pack(side=tk.TOP, fill=tk.X)

        tk.Label(top, text="Mouse + Session:", bg="#ddd").pack(side=tk.LEFT, padx=(8, 4))
        self.cb_ms = ttk.Combobox(top, textvariable=self.sel_ms, values=self.ms_labels, state="readonly", width=35)
        self.cb_ms.pack(side=tk.LEFT)
        self.cb_ms.bind("<<ComboboxSelected>>", self.refresh_grid)

        tk.Label(top, text="Window:", bg="#ddd").pack(side=tk.LEFT, padx=(10, 4))
        self.cb_win = ttk.Combobox(top, textvariable=self.sel_window, values=self.windows, state="readonly", width=6)
        self.cb_win.pack(side=tk.LEFT)
        self.cb_win.bind("<<ComboboxSelected>>", self.refresh_grid)

        tk.Label(top, text="Filter + Limits:", bg="#ddd").pack(side=tk.LEFT, padx=(10, 4))
        self.cb_fl = ttk.Combobox(top, textvariable=self.sel_fl, values=self.filter_limits_labels, state="readonly", width=14)
        self.cb_fl.pack(side=tk.LEFT)
        self.cb_fl.bind("<<ComboboxSelected>>", self.refresh_grid)

        tk.Label(top, text="  |  ", bg="#ddd").pack(side=tk.LEFT, padx=(10, 0))

        tk.Label(top, text="Combo Event:", bg="#ddd", font="Arial 9 bold").pack(side=tk.LEFT, padx=(0, 4))
        self.cb_type = ttk.Combobox(top, textvariable=self.sel_combo_type, values=ORDERED_EVENTS, state="readonly", width=16)
        self.cb_type.pack(side=tk.LEFT)
        self.cb_type.bind("<<ComboboxSelected>>", self.refresh_grid)

        tk.Label(top, text="Combo #:", bg="#ddd").pack(side=tk.LEFT, padx=(10, 4))
        eidx_vals = ["(any)"] + self.event_indices
        self.cb_eidx = ttk.Combobox(top, textvariable=self.sel_eidx, values=eidx_vals, state="readonly", width=8)
        self.cb_eidx.pack(side=tk.LEFT)
        self.cb_eidx.bind("<<ComboboxSelected>>", self.on_global_eidx_change)

        tk.Button(top, text="Next", command=self.next_all).pack(side=tk.LEFT, padx=(12, 4))
        tk.Button(top, text="Prev", command=lambda: self.next_all(-1)).pack(side=tk.LEFT, padx=(0, 8))
        tk.Button(top, text="Refresh", command=self.refresh_grid).pack(side=tk.LEFT, padx=(6, 6))

        self.status = tk.StringVar(value="")
        tk.Label(top, textvariable=self.status, bg="#ddd", fg="#333").pack(side=tk.RIGHT, padx=10)

        # 2. BOTTOM TIMELINE
        self.timeline_frame = tk.Frame(self.root, bg="#1a1a1a", height=100)
        self.timeline_frame.pack(side=tk.BOTTOM, fill=tk.X)
        self.timeline_frame.pack_propagate(False)

        # Network Stats Controls
        stats_frame = tk.Frame(self.timeline_frame, bg="#1a1a1a")
        stats_frame.pack(side=tk.RIGHT, padx=15, pady=10)
        
        tk.Button(stats_frame, text="FILTER REGIONS", command=self.open_filter_dialog, 
                  bg="#555", fg="white", font=("Arial", 9, "bold")).pack(side=tk.LEFT, padx=(0, 5))
                  
        tk.Button(stats_frame, text="COMPARE NETWORK STATS", command=self.open_stats_viewer, 
                  bg="#0055ff", fg="white", font=("Arial", 9, "bold")).pack(side=tk.LEFT)

        self.timeline_info = tk.Label(self.timeline_frame, text="Interactive Timeline - Click to navigate | Ctrl+Click to open side-by-side window", bg="#1a1a1a", fg="#aaa", font=("Arial", 9, "bold"))
        self.timeline_info.pack(side=tk.BOTTOM, fill=tk.X, pady=(0, 2))

        self.timeline_canvas = tk.Canvas(self.timeline_frame, bg="#111", highlightthickness=0)
        self.timeline_canvas.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        # 3. CENTER GRID
        self.grid_frame = tk.Frame(self.root, bg="black")
        self.grid_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True)
        self.grid_frame.bind("<Configure>", self.on_resize)

        self.rebuild_layout()

    def bind_keys(self):
        self.root.bind("<Left>", lambda e: self.next_all(-1))
        self.root.bind("<Right>", lambda e: self.next_all(1))
        self.root.bind("r", lambda e: self.refresh_grid())

    def update_eidx_dropdown(self):
        available_eidx = set()
        for p in self.panels:
            panel_id = self._panel_identity(p["grid_key"])
            eidx_list = self._panel_eidx_list(panel_id)
            available_eidx.update(eidx_list)
            
        sorted_eidx = sorted(list(available_eidx), key=lambda x: int(x) if x.isdigit() else x)
        new_vals = ["(any)"] + sorted_eidx
        
        if list(self.cb_eidx['values']) != new_vals:
            self.cb_eidx['values'] = new_vals
            if self.sel_eidx.get() not in new_vals:
                self.sel_eidx.set("(any)")

    # ---------------- Layout & Refresh ----------------
    def rebuild_layout(self):
        for w in self.grid_frame.winfo_children():
            w.destroy()
        self.panels = []
        self.panel_eidx_pos = {}

        rows, cols = 3, 4
        titles = ORDERED_REGIONS

        for i, title in enumerate(titles):
            fr = tk.Frame(self.grid_frame, bg="white", bd=1)
            fr.grid(row=i // cols, column=i % cols, sticky="nsew", padx=1, pady=1)

            header = tk.Frame(fr, bg="#eee")
            header.pack(side=tk.TOP, fill=tk.X)

            lbl = tk.Label(header, text=title, bg="#eee", font="Arial 9 bold")
            lbl.pack(side=tk.LEFT, fill=tk.X, expand=True)

            cnv = tk.Canvas(fr, bg="black", highlightthickness=0)
            cnv.pack(side=tk.TOP, fill=tk.BOTH, expand=True)
            cnv.bind("<Button-1>", lambda e, key=title: self.open_panel_image(key))

            self.panels.append({"canvas": cnv, "grid_key": title, "label": lbl, "photo": None})

        for r in range(rows):
            self.grid_frame.rowconfigure(r, weight=1)
        for c in range(cols):
            self.grid_frame.columnconfigure(c, weight=1)

        self.refresh_grid()

    def on_resize(self, event=None):
        if self._resize_job is not None:
            self.root.after_cancel(self._resize_job)
        self._resize_job = self.root.after(150, self.refresh_grid)

    def refresh_grid(self, event=None):
        self.update_eidx_dropdown()
        found, missing = 0, 0

        mouse, sess = self._get_selected_mouse_session()

        for p in self.panels:
            canvas = p["canvas"]
            gkey = p["grid_key"]
            canvas.delete("all")

            path, resolved_eidx = self._resolve_path_for_panel(gkey)
            
            if path and os.path.exists(path):
                found += 1
                img = self._load_image(path)

                w = max(50, canvas.winfo_width())
                h = max(50, canvas.winfo_height())

                img_resized = img.resize((w, h), Image.Resampling.LANCZOS)
                ph = ImageTk.PhotoImage(img_resized)
                canvas.create_image(w // 2, h // 2, image=ph, anchor=tk.CENTER)
                p["photo"] = ph
                
                ev_name = self.sel_combo_type.get()
                ev_time = self.event_time_lookup.get((mouse, sess, ev_name, resolved_eidx), -1)
                
                time_str = f"MP: {ev_time:.2f}s" if ev_time >= 0 else "N/A"
                p["label"].config(text=f"{gkey}  |  #{resolved_eidx} @ {time_str}")

            else:
                missing += 1
                p["label"].config(text=f"{gkey}  |  Missing")
                canvas.create_text(
                    10, 10, anchor=tk.NW, text="Not Found",
                    fill="white", font=("Arial", 10, "bold")
                )

        ctx = self.sel_combo_type.get()
        self.status.set(f"Found: {found} | Missing: {missing} | Combo: {ctx} | {self.sel_ms.get()} | {self.sel_fl.get()} | EIDX: {self.sel_eidx.get()}")
        
        self.draw_timeline()

    # ---------------- Global Timeline Drawing ----------------
    def draw_timeline(self):
        self.timeline_canvas.delete("all")
        mouse, sess = self._get_selected_mouse_session()
        events = self.session_timeline_data.get((mouse, sess), [])
        
        if not events:
            return

        w = self.timeline_canvas.winfo_width()
        h = self.timeline_canvas.winfo_height()
        if w < 50 or h < 20: 
            return
        
        pad_x = 40
        pad_y = 25
        
        max_time = max([e[0] for e in events] + [0])
        if max_time <= 0: max_time = 1
        
        self.timeline_canvas.create_line(pad_x, h/2, w - pad_x, h/2, fill="#555", width=2)
        self.timeline_canvas.create_text(pad_x - 10, h/2, text="0s", fill="#aaa", anchor="e", font=("Arial", 8))
        self.timeline_canvas.create_text(w - pad_x + 10, h/2, text=f"{max_time:.0f}s", fill="#aaa", anchor="w", font=("Arial", 8))

        leg_x = pad_x
        for ev in ORDERED_EVENTS:
            if ev in [e[1] for e in events]:
                c = EVENT_COLORS.get(ev, "gray")
                self.timeline_canvas.create_rectangle(leg_x, 5, leg_x + 10, 15, fill=c, outline="")
                self.timeline_canvas.create_text(leg_x + 15, 10, text=ev, fill="#ccc", anchor="w", font=("Arial", 8, "bold"))
                leg_x += 120 

        for t, ev_type, eidx in events:
            if t < 0: continue
            
            x = pad_x + (t / max_time) * (w - 2 * pad_x)
            color = EVENT_COLORS.get(ev_type, "#ffffff")
            
            is_active = (self.sel_combo_type.get() == ev_type and self.sel_eidx.get() == str(eidx))

            rect_w = 3 if is_active else 1.5
            y1 = pad_y if is_active else pad_y + 8
            y2 = h - pad_y if is_active else h - pad_y - 8
            outline = "white" if is_active else ""
            
            item = self.timeline_canvas.create_rectangle(x - rect_w, y1, x + rect_w, y2, fill=color, outline=outline, tags=("event",))

            self.timeline_canvas.tag_bind(item, "<Button-1>", lambda e, et=ev_type, ei=eidx: self.on_timeline_click(e, et, ei))
            self.timeline_canvas.tag_bind(item, "<Enter>", lambda e, et=ev_type, ei=eidx, tt=t: self.on_timeline_hover(et, ei, tt))
            self.timeline_canvas.tag_bind(item, "<Leave>", lambda e: self.on_timeline_leave())

    def on_timeline_click(self, event, ev_type, eidx):
        if event.state & 0x0004:
            self.open_secondary_grid(ev_type, eidx)
        else:
            self.sel_combo_type.set(ev_type)
            self.sel_eidx.set(str(eidx))
            self.panel_eidx_pos = {} 
            self.refresh_grid()

    def on_timeline_hover(self, ev_type, eidx, t):
        self.timeline_info.config(text=f"Event: {ev_type}  |  Index: #{eidx}  |  Midpoint Timestamp: {t:.3f}s", fg="#fff")

    def on_timeline_leave(self):
        self.timeline_info.config(text="Interactive Timeline - Click to navigate | Ctrl+Click to open side-by-side window", fg="#aaa")

    # ---------------- Image Loading ----------------
    def _load_image(self, path):
        img = self._img_cache.get(path)
        if img is None:
            img = Image.open(path)
            if len(self._img_cache) >= self._img_cache_max:
                self._img_cache.pop(next(iter(self._img_cache)))
            self._img_cache[path] = img
        return img

    # ---------------- Data Access Helpers ----------------
    def _get_selected_mouse_session(self):
        label = self.sel_ms.get().strip()
        return self.ms_label_to_pair.get(label, ("", ""))

    def _get_selected_filter_limits(self):
        label = self.sel_fl.get().strip()
        return self.fl_label_to_pair.get(label, ("", ""))

    def _panel_identity(self, grid_key):
        mouse, sess = self._get_selected_mouse_session()
        filt, lims  = self._get_selected_filter_limits()
        win         = self.sel_window.get()
        event       = self.sel_combo_type.get()
        region      = grid_key

        return (mouse, sess, win, filt, lims, event, region)

    def _panel_eidx_list(self, panel_id):
        return self.eidx_by_panelkey.get(panel_id, [])

    def next_all(self, delta=+1):
        if self.sel_eidx.get() != "(any)":
            self.sel_eidx.set("(any)")

        for p in self.panels:
            key = p["grid_key"]
            panel_id = self._panel_identity(key)
            eidx_list = self._panel_eidx_list(panel_id)
            if not eidx_list:
                continue
            cur_pos = self.panel_eidx_pos.get(key, 0)
            cur_pos = (cur_pos + delta) % len(eidx_list)
            self.panel_eidx_pos[key] = cur_pos

        self.refresh_grid()

    def on_global_eidx_change(self, event=None):
        self.panel_eidx_pos = {}
        self.refresh_grid()

    def _resolve_path_for_panel(self, grid_key):
        mouse, sess = self._get_selected_mouse_session()
        filt, lims  = self._get_selected_filter_limits()
        win         = self.sel_window.get()
        global_eidx = self.sel_eidx.get().strip()
        event       = self.sel_combo_type.get()
        region      = grid_key

        if global_eidx and global_eidx != "(any)":
            k = (mouse, sess, win, filt, lims, event, region, global_eidx)
            return self.by_key.get(k), global_eidx

        panel_id = (mouse, sess, win, filt, lims, event, region)
        eidx_list = self._panel_eidx_list(panel_id)
        
        if eidx_list:
            pos = self.panel_eidx_pos.get(grid_key, 0)
            pos = max(0, min(pos, len(eidx_list) - 1))
            chosen = eidx_list[pos]
            k = (mouse, sess, win, filt, lims, event, region, chosen)
            return self.by_key.get(k), chosen

        return None, None

 # ---------------- Stats Integration (Dynamic Heatmaps) ----------------
    def open_filter_dialog(self):
        RegionFilterDialog(self.root, ORDERED_REGIONS, self.active_stats_regions, self.update_filter_state)

    def update_filter_state(self, new_regions):
        self.active_stats_regions = set(new_regions)
        print(f"[UI] Stats Region Filter Applied. {len(self.active_stats_regions)} regions active.")

    def open_stats_viewer(self):
        mouse, sess = self._get_selected_mouse_session()
        event = self.sel_combo_type.get()
        eidx = self.sel_eidx.get()
        
        if eidx == "(any)":
            print("[UI] Action Refused: Select a specific event occurrence from the timeline first.")
            return
            
        key = (mouse, sess, event, str(eidx))
        all_pairs = self.stats_db.get(key, [])
        
        if not all_pairs:
            print(f"[UI] No dynamic stats available yet for: {mouse} | {sess} | {event} | #{eidx}")
            return
            
        filtered_pairs = []
        for ch1, ch2, path in all_pairs:
            base1 = clean_matlab_region(ch1)
            base2 = clean_matlab_region(ch2)
            
            if base1 in self.active_stats_regions and base2 in self.active_stats_regions:
                filtered_pairs.append((ch1, ch2, path))
                
        if not filtered_pairs:
            print("[UI] Action Refused: Your active region filter excluded all available data.")
            return
            
        win = tk.Toplevel(self.root)
        win.title(f"Dynamic Connectivity Tensors | {event} #{eidx} | Filtered: {len(filtered_pairs)} Pairs")
        win.geometry("1600x900")
        
        main_frame = tk.Frame(win, bg="#111")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        canvas = tk.Canvas(main_frame, bg="#111", highlightthickness=0)
        scrollbar = ttk.Scrollbar(main_frame, orient="vertical", command=canvas.yview)
        scrollable_frame = tk.Frame(canvas, bg="#111")
        
        # Frame ID required to force expansion across the canvas
        frame_id = canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        
        # Binds the scrollable frame's width exactly to the canvas width
        def _configure_canvas(event):
            canvas.configure(scrollregion=canvas.bbox("all"))
            canvas.itemconfig(frame_id, width=event.width)
            
        canvas.bind("<Configure>", _configure_canvas)
        canvas.configure(yscrollcommand=scrollbar.set)
        
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        def _on_mousewheel(ev):
            canvas.yview_scroll(int(-1*(ev.delta/120)), "units")
        win.bind("<MouseWheel>", _on_mousewheel)
        
        win.photos = [] 
        
        # Force exactly 3 columns with uniform weight
        for col in range(3):
            scrollable_frame.columnconfigure(col, weight=1, uniform="grid_col")
        
        for i, (ch1, ch2, path) in enumerate(filtered_pairs):
            row = i // 3
            col = i % 3
            
            card = tk.Frame(scrollable_frame, bg="black", bd=2, relief=tk.RIDGE)
            card.grid(row=row, column=col, sticky="nsew", padx=10, pady=10)
            
            lbl = tk.Label(card, text=f"{ch1} vs {ch2}", bg="#222", fg="#00ffcc", font=("Arial", 11, "bold"))
            lbl.pack(side=tk.TOP, fill=tk.X)
            
            # Canvas strictly handles centering the thumbnail as the window stretches
            img_cnv = tk.Canvas(card, bg="black", highlightthickness=0, height=350)
            img_cnv.pack(side=tk.TOP, fill=tk.BOTH, expand=True)
            img_cnv.bind("<Button-1>", lambda e, p=path: self.open_image_viewer(p)) 
            
            try:
                img = Image.open(path)
                # Resolution increased to maintain fidelity when spanning the larger columns
                img.thumbnail((650, 450), Image.Resampling.LANCZOS)
                ph = ImageTk.PhotoImage(img)
                
                # Tags the image object so we can move it dynamically
                img_cnv.create_image(325, 175, image=ph, anchor=tk.CENTER, tags="img_obj")
                
                # Dynamic recentering callback
                def center_image(event, c=img_cnv):
                    c.coords("img_obj", event.width // 2, event.height // 2)
                    
                img_cnv.bind("<Configure>", center_image)
                win.photos.append(ph)
            except Exception:
                img_cnv.create_text(325, 175, text="RENDER FAILED", fill="red", font=("Arial", 12, "bold"))

    # ---------------- Full Screen Interactions ----------------
    def open_panel_image(self, grid_key):
        path, _ = self._resolve_path_for_panel(grid_key)
        if not path or not os.path.exists(path):
            return
        self.open_image_viewer(path)

    def open_image_viewer(self, path):
        win = tk.Toplevel(self.root)
        win.title(os.path.basename(path))
        win.geometry("1200x800")

        frame = tk.Frame(win, bg="black")
        frame.pack(fill=tk.BOTH, expand=True)

        # Removed scrollbars. Canvas expands to fill the entire frame.
        cnv = tk.Canvas(frame, bg="black", highlightthickness=0)
        cnv.pack(fill=tk.BOTH, expand=True)

        win.photo_cache = None # Prevents Python garbage collection from deleting the image

        def resize_to_fit(event):
            w, h = event.width, event.height
            if w < 50 or h < 50: 
                return
                
            img = self._load_image(path)
            
            # Calculate aspect ratios to prevent warping
            img_ratio = img.width / img.height
            cnv_ratio = w / h
            
            if cnv_ratio > img_ratio:
                # Canvas is wider than image -- limit by height
                new_h = h
                new_w = int(h * img_ratio)
            else:
                # Canvas is taller than image -- limit by width
                new_w = w
                new_h = int(w / img_ratio)
                
            img_res = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
            ph = ImageTk.PhotoImage(img_res)
            
            cnv.delete("all")
            cnv.create_image(w // 2, h // 2, image=ph, anchor=tk.CENTER)
            win.photo_cache = ph

        # The image will recalculate its dimensions every time the window is resized
        cnv.bind("<Configure>", resize_to_fit)

    # ---------------- Secondary Grid View (Ctrl+Click) ----------------
    def open_secondary_grid(self, ev_type, eidx):
        mouse, sess = self._get_selected_mouse_session()
        filt, lims  = self._get_selected_filter_limits()
        win         = self.sel_window.get()
        
        win_top = tk.Toplevel(self.root)
        win_top.title(f"Comparison View: {ev_type} #{eidx}  |  {mouse}  |  {sess}")
        win_top.geometry("1000x700")
        
        grid_frame = tk.Frame(win_top, bg="black")
        grid_frame.pack(fill=tk.BOTH, expand=True)
        
        rows, cols = 3, 4
        for r in range(rows):
            grid_frame.rowconfigure(r, weight=1)
        for c in range(cols):
            grid_frame.columnconfigure(c, weight=1)
            
        win_top.photos = {}
        
        for i, region in enumerate(ORDERED_REGIONS):
            fr = tk.Frame(grid_frame, bg="white", bd=1)
            fr.grid(row=i // cols, column=i % cols, sticky="nsew", padx=1, pady=1)
            
            header = tk.Frame(fr, bg="#eee")
            header.pack(side=tk.TOP, fill=tk.X)
            
            lbl = tk.Label(header, text=region, bg="#eee", font=("Arial", 9, "bold"))
            lbl.pack(side=tk.LEFT, fill=tk.X, expand=True)
            
            cnv = tk.Canvas(fr, bg="black", highlightthickness=0)
            cnv.pack(side=tk.TOP, fill=tk.BOTH, expand=True)
            
            k = (mouse, sess, win, filt, lims, ev_type, region, str(eidx))
            path = self.by_key.get(k)
            
            if path and os.path.exists(path):
                cnv.bind("<Button-1>", lambda e, p=path: self.open_image_viewer(p))
                
                def draw_img(event, c=cnv, p=path, r_idx=i):
                    w, h = max(50, event.width), max(50, event.height)
                    img = self._load_image(p)
                    img_res = img.resize((w, h), Image.Resampling.LANCZOS)
                    ph = ImageTk.PhotoImage(img_res)
                    c.delete("all")
                    c.create_image(w//2, h//2, image=ph, anchor=tk.CENTER)
                    win_top.photos[r_idx] = ph 
                
                cnv.bind("<Configure>", draw_img)
            else:
                cnv.create_text(10, 10, anchor=tk.NW, text="Not Found", fill="white", font=("Arial", 10, "bold"))

# ---------------------------------------------------------------------
if __name__ == "__main__":
    root = tk.Tk()
    app = ComboMaster(root)
    root.mainloop()