import os
import csv
import tkinter as tk
from tkinter import ttk
from PIL import Image, ImageTk

# ---------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------
IMG_DIR = r"D:\HOF DATA\ACTIVE DATA\PYTHON_UI_DATA\PRE GENERATED GRAPHS"
LOG_FILE = os.path.join(IMG_DIR, "Ultra_Master_Log.csv")

ORDERED_REGIONS = [
    'LeftPOR', 'RightPOR', 'LeftPER', 'RightPER',
    'LeftOFC', 'RightOFC', 'LeftACC', 'RightACC',
    'LeftDHC', 'RightDHC', 'LeftRSC', 'RightRSC'
]

COMBO_TYPES = ['Click-Noise', 'HighTone-LowTone']
ORDERED_EVENTS = ['Click', 'Noise', 'HighTone', 'LowTone', 'PelletDelivery', 'MagPoke', 'EndOfBox']
ORDERED_FILTERS = ['Raw', 'Delta', 'Theta', 'Gamma']

# Distinct colors for the timeline mapping
EVENT_COLORS = {
    'Click': '#1f77b4',        
    'Noise': '#ff7f0e',        
    'HighTone': '#2ca02c',     
    'LowTone': '#d62728',      
    'PelletDelivery': '#9467bd', 
    'MagPoke': '#8c564b',      
    'EndOfBox': '#e377c2'      
}

# ---------------------------------------------------------------------
# HELPER FUNCTIONS
# ---------------------------------------------------------------------
def ms_key(mouse, session):
    return f"{mouse} | {session}" if session else f"{mouse} | (no-session)"

def fl_key(filt, limits):
    return f"{filt} {limits}".strip()

# ---------------------------------------------------------------------
# UI APP
# ---------------------------------------------------------------------
class ComboMaster:
    def __init__(self, root):
        self.root = root
        self.root.title("NeuroScope Dual-Combo Viewer - Timeline Edition")
        try:
            self.root.state("zoomed")
        except tk.TclError:
            self.root.geometry("1500x950")

        # Database
        self.records = []
        self.by_key = {} 
        self.event_time_lookup = {} 
        self.session_timeline_data = {} 
        self.session_combos = {} # (mouse, session, combo_type) -> list of combo dicts

        # Dropdown options
        self.ms_pairs = []
        self.ms_labels = []
        self.ms_label_to_pair = {}

        self.filter_limits = []
        self.filter_limits_labels = []
        self.fl_label_to_pair = {}

        self.windows = []
        self.combo_indices = []

        # Selections
        self.sel_ms = tk.StringVar()
        self.sel_fl = tk.StringVar()
        self.sel_window = tk.StringVar()
        self.sel_combo_type = tk.StringVar(value="Click-Noise")
        self.sel_combo_idx = tk.StringVar(value="(any)")

        # Per-panel override (for browsing different combos simultaneously)
        self.panel_combo_pos = {}

        # UI References
        self.panels = []
        self._resize_job = None
        self._img_cache = {}
        self._img_cache_max = 300

        # Boot Sequence
        self.scan_database()
        self.setup_ui()
        self.bind_keys()

    # ---------------- Database & Combo Logic ----------------
    def scan_database(self):
        if not os.path.exists(LOG_FILE):
            print(f"[CRITICAL] Master log not found at: {LOG_FILE}")
            return

        ms_pairs = set()
        fl_pairs = set()
        wins = set()

        by_key = {}
        records = []
        missing_images = 0

        # 1. Ingest CSV Data
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

                    # Store exact paths
                    key = (mouse, session, win, filt, limits, event, region, event_index)
                    by_key[key] = path

                except KeyError as e:
                    print(f"[CRITICAL] Missing expected column in CSV: {e}")
                    return

        # 2. Build Timeline Data
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

        # 3. Detect Paired Combos (Within 11 seconds)
        for (mouse, sess), evs in self.session_timeline_data.items():
            click_noise = []
            high_low = []
            
            skip_eidx = set() # Prevent double-counting the same event
            
            for i in range(len(evs)):
                t1, ev1, e1 = evs[i]
                if (ev1, e1) in skip_eidx: continue
                
                if ev1 == 'Click':
                    for j in range(i+1, len(evs)):
                        t2, ev2, e2 = evs[j]
                        if t2 - t1 > 11.0: break # Window exceeded
                        if ev2 == 'Noise' and (ev2, e2) not in skip_eidx:
                            click_noise.append({'idx': len(click_noise)+1, 'eidx1': e1, 'eidx2': e2, 't1': t1, 't2': t2})
                            skip_eidx.add((ev1, e1))
                            skip_eidx.add((ev2, e2))
                            break

                elif ev1 == 'HighTone':
                    for j in range(i+1, len(evs)):
                        t2, ev2, e2 = evs[j]
                        if t2 - t1 > 11.0: break
                        if ev2 == 'LowTone' and (ev2, e2) not in skip_eidx:
                            high_low.append({'idx': len(high_low)+1, 'eidx1': e1, 'eidx2': e2, 't1': t1, 't2': t2})
                            skip_eidx.add((ev1, e1))
                            skip_eidx.add((ev2, e2))
                            break

            if click_noise:
                self.session_combos[(mouse, sess, 'Click-Noise')] = click_noise
            if high_low:
                self.session_combos[(mouse, sess, 'HighTone-LowTone')] = high_low

        self.records = records
        self.by_key = by_key

        # 4. Populate Dropdowns
        ms_pairs_sorted = sorted(list(ms_pairs), key=lambda x: (x[0], x[1]))
        self.ms_pairs = ms_pairs_sorted
        self.ms_labels = [ms_key(m, s) for m, s in ms_pairs_sorted]
        self.ms_label_to_pair = {ms_key(m, s): (m, s) for m, s in ms_pairs_sorted}

        fl_pairs_sorted = sorted(list(fl_pairs), key=lambda p: (ORDERED_FILTERS.index(p[0]) if p[0] in ORDERED_FILTERS else 999, p[1]))
        self.filter_limits = fl_pairs_sorted
        self.filter_limits_labels = [fl_key(f, lim) for f, lim in fl_pairs_sorted]
        self.fl_label_to_pair = {fl_key(f, lim): (f, lim) for f, lim in fl_pairs_sorted}

        self.windows = sorted(list(wins), key=lambda x: int(x[1:]) if x[1:].isdigit() else x)

        # Set Defaults
        if self.ms_labels:
            self.sel_ms.set(self.ms_labels[0])
        if self.windows:
            self.sel_window.set(self.windows[0])
        if self.filter_limits_labels:
            self.sel_fl.set(self.filter_limits_labels[0])

        self.sel_combo_idx.set("(any)")

        print(f"[DB] Indexed {len(self.records)} images.")
        combo_count = sum(len(v) for v in self.session_combos.values())
        print(f"[DB] Detected {combo_count} valid paired combos across all sessions.")
        if missing_images > 0:
            print(f"[WARNING] {missing_images} files listed in CSV were not found on disk.")

    # ---------------- UI Setup ----------------
    def setup_ui(self):
        # 1. TOP CONTROLS
        top = tk.Frame(self.root, bg="#ddd", height=56)
        top.pack(side=tk.TOP, fill=tk.X)

        tk.Label(top, text="Mouse + Session:", bg="#ddd").pack(side=tk.LEFT, padx=(8, 4))
        self.cb_ms = ttk.Combobox(top, textvariable=self.sel_ms, values=self.ms_labels, state="readonly", width=30)
        self.cb_ms.pack(side=tk.LEFT)
        self.cb_ms.bind("<<ComboboxSelected>>", self.refresh_grid)

        tk.Label(top, text="Window:", bg="#ddd").pack(side=tk.LEFT, padx=(10, 4))
        self.cb_win = ttk.Combobox(top, textvariable=self.sel_window, values=self.windows, state="readonly", width=6)
        self.cb_win.pack(side=tk.LEFT)
        self.cb_win.bind("<<ComboboxSelected>>", self.refresh_grid)

        tk.Label(top, text="Filter + Limits:", bg="#ddd").pack(side=tk.LEFT, padx=(10, 4))
        self.cb_fl = ttk.Combobox(top, textvariable=self.sel_fl, values=self.filter_limits_labels, state="readonly", width=12)
        self.cb_fl.pack(side=tk.LEFT)
        self.cb_fl.bind("<<ComboboxSelected>>", self.refresh_grid)

        tk.Label(top, text="  |  ", bg="#ddd").pack(side=tk.LEFT, padx=(6, 0))

        tk.Label(top, text="Combo Type:", bg="#ddd", font="Arial 9 bold").pack(side=tk.LEFT, padx=(0, 4))
        self.cb_type = ttk.Combobox(top, textvariable=self.sel_combo_type, values=COMBO_TYPES, state="readonly", width=16)
        self.cb_type.pack(side=tk.LEFT)
        self.cb_type.bind("<<ComboboxSelected>>", self.refresh_grid)

        tk.Label(top, text="Combo Set #:", bg="#ddd", font="Arial 9 bold").pack(side=tk.LEFT, padx=(10, 4))
        self.cb_cidx = ttk.Combobox(top, textvariable=self.sel_combo_idx, state="readonly", width=8)
        self.cb_cidx.pack(side=tk.LEFT)
        self.cb_cidx.bind("<<ComboboxSelected>>", self.on_global_combo_change)

        tk.Button(top, text="Next", command=self.next_all).pack(side=tk.LEFT, padx=(12, 4))
        tk.Button(top, text="Prev", command=lambda: self.next_all(-1)).pack(side=tk.LEFT, padx=(0, 8))
        tk.Button(top, text="Refresh", command=self.refresh_grid).pack(side=tk.LEFT, padx=(6, 6))

        self.status = tk.StringVar(value="")
        tk.Label(top, textvariable=self.status, bg="#ddd", fg="#333").pack(side=tk.RIGHT, padx=10)

        # 2. BOTTOM TIMELINE
        self.timeline_frame = tk.Frame(self.root, bg="#1a1a1a", height=120)
        self.timeline_frame.pack(side=tk.BOTTOM, fill=tk.X)
        self.timeline_frame.pack_propagate(False)

        self.timeline_info = tk.Label(self.timeline_frame, text="Interactive Timeline - Click to view Combo | Ctrl+Click to open side-by-side window", bg="#1a1a1a", fg="#aaa", font=("Arial", 9, "bold"))
        self.timeline_info.pack(side=tk.BOTTOM, fill=tk.X, pady=(0, 2))

        self.timeline_canvas = tk.Canvas(self.timeline_frame, bg="#111", highlightthickness=0)
        self.timeline_canvas.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        # 3. CENTER DUAL-GRID
        self.grid_frame = tk.Frame(self.root, bg="black")
        self.grid_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True)
        self.grid_frame.bind("<Configure>", self.on_resize)

        self.rebuild_layout()

    def bind_keys(self):
        self.root.bind("<Left>", lambda e: self.next_all(-1))
        self.root.bind("<Right>", lambda e: self.next_all(1))
        self.root.bind("r", lambda e: self.refresh_grid())

    # ---------------- Layout & Refresh ----------------
    def rebuild_layout(self):
        for w in self.grid_frame.winfo_children():
            w.destroy()
        self.panels = []
        self.panel_combo_pos = {}

        rows, cols = 3, 4
        
        for i, title in enumerate(ORDERED_REGIONS):
            fr = tk.Frame(self.grid_frame, bg="#444", bd=1)
            fr.grid(row=i // cols, column=i % cols, sticky="nsew", padx=2, pady=2)

            header = tk.Frame(fr, bg="#2b2b2b")
            header.pack(side=tk.TOP, fill=tk.X)

            lbl = tk.Label(header, text=title, bg="#2b2b2b", fg="#fff", font=("Arial", 9, "bold"))
            lbl.pack(side=tk.LEFT, fill=tk.X, expand=True, pady=2)

            # Dual Canvas Container
            cnv_frame = tk.Frame(fr, bg="black")
            cnv_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

            cnv1 = tk.Canvas(cnv_frame, bg="#0a0a0a", highlightthickness=0)
            cnv1.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 1))
            cnv1.bind("<Button-1>", lambda e, k=title: self.open_panel_image(k))

            cnv2 = tk.Canvas(cnv_frame, bg="#0a0a0a", highlightthickness=0)
            cnv2.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(1, 0))
            cnv2.bind("<Button-1>", lambda e, k=title: self.open_panel_image(k))

            self.panels.append({
                "cnv1": cnv1, "cnv2": cnv2, 
                "grid_key": title, "label": lbl, 
                "photo1": None, "photo2": None
            })

        for r in range(rows):
            self.grid_frame.rowconfigure(r, weight=1)
        for c in range(cols):
            self.grid_frame.columnconfigure(c, weight=1)

        self.refresh_grid()

    def update_combo_dropdown(self):
        mouse, sess = self._get_selected_mouse_session()
        ctype = self.sel_combo_type.get()
        combos = self.session_combos.get((mouse, sess, ctype), [])
        
        new_vals = ["(any)"] + [str(c['idx']) for c in combos]
        
        if list(self.cb_cidx['values']) != new_vals:
            self.cb_cidx['values'] = new_vals
            if self.sel_combo_idx.get() not in new_vals:
                self.sel_combo_idx.set("(any)")

    def on_resize(self, event=None):
        if self._resize_job is not None:
            self.root.after_cancel(self._resize_job)
        self._resize_job = self.root.after(150, self.refresh_grid)

    def refresh_grid(self, event=None):
        self.update_combo_dropdown()
        mouse, sess = self._get_selected_mouse_session()
        ctype = self.sel_combo_type.get()
        combos = self.session_combos.get((mouse, sess, ctype), [])
        
        found = 0

        # Determine target combo to display
        active_combo = None
        c_idx_str = self.sel_combo_idx.get()
        
        if combos:
            if c_idx_str == "(any)":
                pos = self.panel_combo_pos.get("global", 0) % len(combos)
                active_combo = combos[pos]
            else:
                try:
                    target_idx = int(c_idx_str)
                    active_combo = next((c for c in combos if c['idx'] == target_idx), combos[0])
                except ValueError:
                    active_combo = combos[0]

        ev1_type, ev2_type = ctype.split('-')
        filt, lims = self._get_selected_filter_limits()
        win = self.sel_window.get()

        for p in self.panels:
            c1, c2 = p["cnv1"], p["cnv2"]
            gkey = p["grid_key"]
            c1.delete("all")
            c2.delete("all")

            if not active_combo:
                p["label"].config(text=f"{gkey}  |  No {ctype} combos detected.")
                c1.create_text(10, 10, anchor=tk.NW, text="N/A", fill="#555")
                c2.create_text(10, 10, anchor=tk.NW, text="N/A", fill="#555")
                continue

            path1 = self.by_key.get((mouse, sess, win, filt, lims, ev1_type, gkey, active_combo['eidx1']))
            path2 = self.by_key.get((mouse, sess, win, filt, lims, ev2_type, gkey, active_combo['eidx2']))

            delta_t = active_combo['t2'] - active_combo['t1']
            header_text = f"{gkey}  |  {ev1_type} #{active_combo['eidx1']} ({active_combo['t1']:.1f}s)  ->  {ev2_type} #{active_combo['eidx2']} ({active_combo['t2']:.1f}s)  [Δ {delta_t:.2f}s]"
            p["label"].config(text=header_text)

            # Draw Left
            if path1 and os.path.exists(path1):
                img1 = self._load_image(path1)
                w, h = max(50, c1.winfo_width()), max(50, c1.winfo_height())
                p["photo1"] = ImageTk.PhotoImage(img1.resize((w, h), Image.Resampling.LANCZOS))
                c1.create_image(w // 2, h // 2, image=p["photo1"], anchor=tk.CENTER)
                found += 1
            else:
                c1.create_text(10, 10, anchor=tk.NW, text="Not Found", fill="white")

            # Draw Right
            if path2 and os.path.exists(path2):
                img2 = self._load_image(path2)
                w, h = max(50, c2.winfo_width()), max(50, c2.winfo_height())
                p["photo2"] = ImageTk.PhotoImage(img2.resize((w, h), Image.Resampling.LANCZOS))
                c2.create_image(w // 2, h // 2, image=p["photo2"], anchor=tk.CENTER)
                found += 1
            else:
                c2.create_text(10, 10, anchor=tk.NW, text="Not Found", fill="white")

        status_text = f"Images loaded: {found} | Combo Target: {ctype} #{active_combo['idx'] if active_combo else 'None'}"
        self.status.set(status_text)
        
        self.draw_timeline(active_combo)

    # ---------------- Global Timeline Drawing ----------------
    def draw_timeline(self, active_combo):
        self.timeline_canvas.delete("all")
        mouse, sess = self._get_selected_mouse_session()
        events = self.session_timeline_data.get((mouse, sess), [])
        
        if not events: return

        w = self.timeline_canvas.winfo_width()
        h = self.timeline_canvas.winfo_height()
        if w < 50 or h < 20: return
        
        pad_x = 40
        pad_y = 35 # Leave room at top for brackets
        
        max_time = max([e[0] for e in events] + [0])
        if max_time <= 0: max_time = 1
        
        # Central axis
        self.timeline_canvas.create_line(pad_x, h/2 + 10, w - pad_x, h/2 + 10, fill="#555", width=2)
        self.timeline_canvas.create_text(pad_x - 10, h/2 + 10, text="0s", fill="#aaa", anchor="e", font=("Arial", 8))
        self.timeline_canvas.create_text(w - pad_x + 10, h/2 + 10, text=f"{max_time:.0f}s", fill="#aaa", anchor="w", font=("Arial", 8))

        # Legend
        leg_x = pad_x
        for ev in ORDERED_EVENTS:
            if ev in [e[1] for e in events]:
                c = EVENT_COLORS.get(ev, "gray")
                self.timeline_canvas.create_rectangle(leg_x, 5, leg_x + 10, 15, fill=c, outline="")
                self.timeline_canvas.create_text(leg_x + 15, 10, text=ev, fill="#ccc", anchor="w", font=("Arial", 8, "bold"))
                leg_x += 85

        # Draw Events
        ctype = self.sel_combo_type.get()
        ev1_type, ev2_type = ctype.split('-')

        for t, ev_type, eidx in events:
            if t < 0: continue
            
            x = pad_x + (t / max_time) * (w - 2 * pad_x)
            color = EVENT_COLORS.get(ev_type, "#ffffff")
            
            is_active_element = False
            if active_combo:
                if (ev_type == ev1_type and eidx == active_combo['eidx1']) or \
                   (ev_type == ev2_type and eidx == active_combo['eidx2']):
                    is_active_element = True

            rect_w = 3 if is_active_element else 1.5
            y1 = pad_y if is_active_element else pad_y + 8
            y2 = h - 15 if is_active_element else h - 23
            outline = "white" if is_active_element else ""
            
            item = self.timeline_canvas.create_rectangle(x - rect_w, y1, x + rect_w, y2, fill=color, outline=outline, tags=("event",))

            self.timeline_canvas.tag_bind(item, "<Button-1>", lambda e, et=ev_type, ei=eidx: self.on_timeline_click(e, et, ei))
            self.timeline_canvas.tag_bind(item, "<Enter>", lambda e, et=ev_type, ei=eidx, tt=t: self.on_timeline_hover(et, ei, tt))
            self.timeline_canvas.tag_bind(item, "<Leave>", lambda e: self.on_timeline_leave())

        # Draw Combo Bracket
        if active_combo:
            x1 = pad_x + (active_combo['t1'] / max_time) * (w - 2 * pad_x)
            x2 = pad_x + (active_combo['t2'] / max_time) * (w - 2 * pad_x)
            y_b = pad_y - 5
            
            self.timeline_canvas.create_line(x1, y_b+5, x1, y_b, x2, y_b, x2, y_b+5, fill="white", width=2)
            delta = active_combo['t2'] - active_combo['t1']
            self.timeline_canvas.create_text((x1+x2)/2, y_b - 8, text=f"Δ {delta:.2f}s", fill="white", font=("Arial", 9, "bold"))

    def on_timeline_click(self, event, ev_type, eidx):
        mouse, sess = self._get_selected_mouse_session()
        ctype = self.sel_combo_type.get()
        combos = self.session_combos.get((mouse, sess, ctype), [])
        
        found_combo = None
        for c in combos:
            if (c['eidx1'] == eidx and ctype.startswith(ev_type)) or \
               (c['eidx2'] == eidx and ctype.endswith(ev_type)):
                found_combo = c
                break
                
        if found_combo:
            if event.state & 0x0004: # Ctrl Key Modifier
                self.open_secondary_grid(ctype, found_combo)
            else:
                self.sel_combo_idx.set(str(found_combo['idx']))
                self.panel_combo_pos["global"] = combos.index(found_combo)
                self.refresh_grid()

    def on_timeline_hover(self, ev_type, eidx, t):
        self.timeline_info.config(text=f"Event: {ev_type}  |  Index: #{eidx}  |  Timestamp: {t:.3f}s", fg="#fff")

    def on_timeline_leave(self):
        self.timeline_info.config(text="Interactive Timeline - Click to view Combo | Ctrl+Click to open side-by-side window", fg="#aaa")

    # ---------------- Data Access Helpers ----------------
    def _get_selected_mouse_session(self):
        label = self.sel_ms.get().strip()
        return self.ms_label_to_pair.get(label, ("", ""))

    def _get_selected_filter_limits(self):
        label = self.sel_fl.get().strip()
        return self.fl_label_to_pair.get(label, ("", ""))

    def _load_image(self, path):
        img = self._img_cache.get(path)
        if img is None:
            img = Image.open(path)
            if len(self._img_cache) >= self._img_cache_max:
                self._img_cache.pop(next(iter(self._img_cache)))
            self._img_cache[path] = img
        return img

    def on_global_combo_change(self, event=None):
        self.refresh_grid()

    def next_all(self, delta=+1):
        if self.sel_combo_idx.get() != "(any)":
            self.sel_combo_idx.set("(any)")

        cur_pos = self.panel_combo_pos.get("global", 0)
        self.panel_combo_pos["global"] = cur_pos + delta
        self.refresh_grid()

    # ---------------- Full Screen Interactions ----------------
    def get_current_combo_data(self, grid_key):
        mouse, sess = self._get_selected_mouse_session()
        ctype = self.sel_combo_type.get()
        combos = self.session_combos.get((mouse, sess, ctype), [])
        
        if not combos: return None, None, None
        
        c_idx_str = self.sel_combo_idx.get()
        if c_idx_str == "(any)":
            pos = self.panel_combo_pos.get("global", 0) % len(combos)
            combo = combos[pos]
        else:
            try:
                target_idx = int(c_idx_str)
                combo = next((c for c in combos if c['idx'] == target_idx), combos[0])
            except ValueError:
                combo = combos[0]

        ev1_type, ev2_type = ctype.split('-')
        filt, lims = self._get_selected_filter_limits()
        win = self.sel_window.get()

        path1 = self.by_key.get((mouse, sess, win, filt, lims, ev1_type, grid_key, combo['eidx1']))
        path2 = self.by_key.get((mouse, sess, win, filt, lims, ev2_type, grid_key, combo['eidx2']))
        
        return path1, path2, combo

    def open_panel_image(self, grid_key):
        path1, path2, combo = self.get_current_combo_data(grid_key)
        if not path1 and not path2: return
        self.open_dual_viewer(path1, path2, grid_key, combo)

    def open_dual_viewer(self, path1, path2, region, combo):
        win = tk.Toplevel(self.root)
        ctype = self.sel_combo_type.get()
        ev1_type, ev2_type = ctype.split('-')
        
        delta = combo['t2'] - combo['t1']
        win.title(f"{region}  |  {ev1_type} #{combo['eidx1']} -> {ev2_type} #{combo['eidx2']}  [Δ {delta:.2f}s]")
        win.geometry("1400x700")

        frame = tk.Frame(win, bg="black")
        frame.pack(fill=tk.BOTH, expand=True)
        
        # Two internal frames to hold canvas + scrollbars independently
        f_left = tk.Frame(frame, bg="black")
        f_left.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=1)
        f_right = tk.Frame(frame, bg="black")
        f_right.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=1)

        def setup_scroll_canvas(parent, path, text_overlay):
            cnv = tk.Canvas(parent, bg="#111", highlightthickness=0)
            cnv.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

            ys = ttk.Scrollbar(parent, orient="vertical", command=cnv.yview)
            ys.pack(side=tk.RIGHT, fill=tk.Y)
            xs = ttk.Scrollbar(parent, orient="horizontal", command=cnv.xview)
            xs.pack(side=tk.BOTTOM, fill=tk.X)
            cnv.configure(yscrollcommand=ys.set, xscrollcommand=xs.set)

            if path and os.path.exists(path):
                img = self._load_image(path)
                ph = ImageTk.PhotoImage(img)
                cnv.create_image(0, 0, image=ph, anchor=tk.NW)
                cnv.image = ph
                cnv.config(scrollregion=(0, 0, img.size[0], img.size[1]))
            else:
                cnv.create_text(20, 20, anchor=tk.NW, text=f"Missing: {text_overlay}", fill="white")

        setup_scroll_canvas(f_left, path1, ev1_type)
        setup_scroll_canvas(f_right, path2, ev2_type)

    def open_secondary_grid(self, ctype, combo):
        mouse, sess = self._get_selected_mouse_session()
        filt, lims  = self._get_selected_filter_limits()
        win_size    = self.sel_window.get()
        ev1_type, ev2_type = ctype.split('-')
        
        win_top = tk.Toplevel(self.root)
        delta = combo['t2'] - combo['t1']
        win_top.title(f"Comparison View: {ctype} Set #{combo['idx']}  |  {mouse}  |  {sess}  [Δ {delta:.2f}s]")
        win_top.geometry("1400x900")
        
        grid_frame = tk.Frame(win_top, bg="black")
        grid_frame.pack(fill=tk.BOTH, expand=True)
        
        rows, cols = 3, 4
        for r in range(rows): grid_frame.rowconfigure(r, weight=1)
        for c in range(cols): grid_frame.columnconfigure(c, weight=1)
            
        win_top.photos = {} 
        
        for i, region in enumerate(ORDERED_REGIONS):
            fr = tk.Frame(grid_frame, bg="#444", bd=1)
            fr.grid(row=i // cols, column=i % cols, sticky="nsew", padx=2, pady=2)
            
            header = tk.Frame(fr, bg="#2b2b2b")
            header.pack(side=tk.TOP, fill=tk.X)
            
            lbl = tk.Label(header, text=region, bg="#2b2b2b", fg="#fff", font=("Arial", 9, "bold"))
            lbl.pack(side=tk.LEFT, fill=tk.X, expand=True)
            
            cnv_frame = tk.Frame(fr, bg="black")
            cnv_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

            c1 = tk.Canvas(cnv_frame, bg="#0a0a0a", highlightthickness=0)
            c1.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 1))
            c2 = tk.Canvas(cnv_frame, bg="#0a0a0a", highlightthickness=0)
            c2.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(1, 0))

            path1 = self.by_key.get((mouse, sess, win_size, filt, lims, ev1_type, region, combo['eidx1']))
            path2 = self.by_key.get((mouse, sess, win_size, filt, lims, ev2_type, region, combo['eidx2']))
            
            c1.bind("<Button-1>", lambda e, p1=path1, p2=path2, r=region, c=combo: self.open_dual_viewer(p1, p2, r, c))
            c2.bind("<Button-1>", lambda e, p1=path1, p2=path2, r=region, c=combo: self.open_dual_viewer(p1, p2, r, c))
            
            def draw_imgs(event, canvas1=c1, canvas2=c2, p1=path1, p2=path2, r_idx=i):
                w, h = max(50, canvas1.winfo_width()), max(50, canvas1.winfo_height())
                
                if p1 and os.path.exists(p1):
                    img1 = self._load_image(p1).resize((w, h), Image.Resampling.LANCZOS)
                    ph1 = ImageTk.PhotoImage(img1)
                    canvas1.delete("all")
                    canvas1.create_image(w//2, h//2, image=ph1, anchor=tk.CENTER)
                    win_top.photos[f"{r_idx}_1"] = ph1 
                else:
                    canvas1.create_text(10, 10, anchor=tk.NW, text="N/A", fill="white")

                w2, h2 = max(50, canvas2.winfo_width()), max(50, canvas2.winfo_height())
                if p2 and os.path.exists(p2):
                    img2 = self._load_image(p2).resize((w2, h2), Image.Resampling.LANCZOS)
                    ph2 = ImageTk.PhotoImage(img2)
                    canvas2.delete("all")
                    canvas2.create_image(w2//2, h2//2, image=ph2, anchor=tk.CENTER)
                    win_top.photos[f"{r_idx}_2"] = ph2 
                else:
                    canvas2.create_text(10, 10, anchor=tk.NW, text="N/A", fill="white")

            c1.bind("<Configure>", draw_imgs)

# ---------------------------------------------------------------------
if __name__ == "__main__":
    root = tk.Tk()
    app = ComboMaster(root)
    root.mainloop()