import tkinter as tk
from tkinter import ttk
import pandas as pd
import os
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2Tk
import matplotlib.colors as mcolors

# --- CONFIGURATION ---
FILE_PATH = r"D:\HOF DATA\ACTIVE DATA\All_Events_Summary_Global_Timeline_Input.xlsx"

class EventViewerApp:
    def __init__(self, root, df):
        self.root = root
        self.root.title(f"Global Timeline - {os.path.basename(FILE_PATH)}")
        self.root.geometry("1400x800")
        
        # Data
        self.df = df
        self.current_start_time = 0.0
        self.session_max_time = 100.0 # Placeholder
        self.window_width = 30.0
        
        # Colors
        self.unique_events = sorted(self.df['Event_Name'].unique())
        self.color_map = self._generate_colors(self.unique_events)

        # --- LAYOUT ---
        # 1. TOP CONTROL
        top_frame = tk.Frame(root, bg="#eee", height=40)
        top_frame.pack(side=tk.TOP, fill=tk.X)
        
        tk.Label(top_frame, text="Session:", bg="#eee", font=("Arial", 10, "bold")).pack(side=tk.LEFT, padx=10, pady=5)
        
        self.session_var = tk.StringVar()
        self.session_combo = ttk.Combobox(top_frame, textvariable=self.session_var, state="readonly", width=40)
        self.session_combo.pack(side=tk.LEFT, padx=5, pady=5)
        self.session_combo.bind("<<ComboboxSelected>>", self.on_session_change)

        # 2. MAIN CONTENT AREA
        content_frame = tk.Frame(root)
        content_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        # LEFT PANEL: INFO
        left_panel = tk.Frame(content_frame, width=220, bg="#f9f9f9", relief=tk.RIDGE, bd=2)
        left_panel.pack(side=tk.LEFT, fill=tk.Y)
        left_panel.pack_propagate(False)

        tk.Label(left_panel, text="Event Details", font=("Arial", 12, "bold", "underline"), bg="#f9f9f9").pack(pady=(20, 10))
        
        self.var_name = tk.StringVar(value="-")
        self.var_ttl = tk.StringVar(value="-")
        self.var_time = tk.StringVar(value="-")
        self.var_repeats = tk.StringVar(value="-")

        self._create_info_row(left_panel, "Event Name:", self.var_name)
        self._create_info_row(left_panel, "TTL Code:", self.var_ttl)
        self._create_info_row(left_panel, "Start Time:", self.var_time)
        self._create_info_row(left_panel, "Burst Repeats:", self.var_repeats)
        
        # CENTER PANEL: GRAPH
        self.fig, self.ax = plt.subplots(figsize=(10, 6))
        self.fig.subplots_adjust(left=0.05, right=0.85, top=0.9, bottom=0.15)
        
        self.canvas = FigureCanvasTkAgg(self.fig, master=content_frame)
        self.canvas_widget = self.canvas.get_tk_widget()
        self.canvas_widget.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        # 3. BOTTOM: NAVIGATION
        nav_frame = tk.Frame(root, bg="#e0e0e0", height=50, bd=1, relief=tk.RAISED)
        nav_frame.pack(side=tk.BOTTOM, fill=tk.X)
        
        tk.Label(nav_frame, text="Window (s):", bg="#e0e0e0").pack(side=tk.LEFT, padx=(20, 5))
        self.width_var = tk.DoubleVar(value=30.0)
        entry = tk.Entry(nav_frame, textvariable=self.width_var, width=5)
        entry.pack(side=tk.LEFT, padx=5)
        entry.bind('<Return>', lambda e: self.update_view_limit())
        
        tk.Button(nav_frame, text="<< Prev", command=self.scroll_prev).pack(side=tk.LEFT, padx=20)
        tk.Button(nav_frame, text="Next >>", command=self.scroll_next).pack(side=tk.LEFT, padx=5)
        
        # NEW: Fit All Button
        tk.Button(nav_frame, text="Fit All", command=self.fit_all_view, bg="#d0e0ff").pack(side=tk.LEFT, padx=30)

        # --- INITIALIZATION ---
        self.highlight_rect = patches.Rectangle((0,0), 1, 1, linewidth=2, edgecolor='red', facecolor='yellow', alpha=0.3, visible=False)
        self.ax.add_patch(self.highlight_rect)

        self.canvas.mpl_connect("motion_notify_event", self.hover)
        
        sessions = sorted(self.df['Session'].unique())
        self.session_combo['values'] = sessions
        if sessions:
            self.session_combo.current(0)
            self.on_session_change()

    def _create_info_row(self, parent, label_text, variable):
        frame = tk.Frame(parent, bg="#f9f9f9")
        frame.pack(fill=tk.X, padx=10, pady=5)
        tk.Label(frame, text=label_text, font=("Arial", 9, "bold"), bg="#f9f9f9", anchor="w").pack(fill=tk.X)
        tk.Label(frame, textvariable=variable, font=("Arial", 10), bg="white", relief=tk.SUNKEN, anchor="w", padx=5).pack(fill=tk.X)

    def _generate_colors(self, items):
        colors = list(mcolors.TABLEAU_COLORS.values())
        mapping = {}
        for i, item in enumerate(items):
            mapping[item] = colors[i % len(colors)]
        return mapping

    def on_session_change(self, event=None):
        self.current_start_time = 0.0
        self.draw_plot()

    def draw_plot(self):
        selected_session = self.session_var.get()
        if not selected_session:
            return

        self.ax.clear()
        dff = self.df[self.df['Session'] == selected_session]
        
        # Calculate Max Time for this session (plus small padding)
        if not dff.empty:
            self.session_max_time = dff['Visual_End'].max() + 0.5
        else:
            self.session_max_time = 30.0

        self.bars_collections = [] 
        y_pos = 10
        height = 5
        
        for event_name in self.unique_events:
            subset = dff[dff['Event_Name'] == event_name]
            if subset.empty:
                continue
                
            durations = subset['Visual_End'] - subset['Start_Time']
            xranges = list(zip(subset['Start_Time'], durations))
            color = self.color_map.get(event_name, 'gray')
            
            coll = self.ax.broken_barh(
                xranges, (y_pos, height), 
                facecolors=color, 
                label=event_name, 
                edgecolors='black', linewidth=0.5, alpha=0.8
            )
            coll.local_data = subset
            self.bars_collections.append(coll)

        self.ax.set_yticks([])
        self.ax.set_xlabel("Time (seconds)")
        self.ax.set_title(f"Session: {selected_session}", fontweight='bold')
        self.ax.grid(True, axis='x', linestyle=':', alpha=0.6)
        self.ax.legend(loc='upper left', bbox_to_anchor=(1.02, 1), borderaxespad=0, title="Event Types")
        
        self.highlight_rect = patches.Rectangle((0,0), 1, 1, linewidth=2, edgecolor='red', facecolor='none', visible=False)
        self.ax.add_patch(self.highlight_rect)

        self.update_view_limit()

    def fit_all_view(self):
        """Sets the window to cover the entire session."""
        self.current_start_time = 0
        # Set width to max time (rounded up)
        self.width_var.set(round(self.session_max_time + 1, 1))
        self.update_view_limit()

    def update_view_limit(self):
        """Updates X-axis with boundary clamping."""
        try:
            width = self.width_var.get()
        except:
            width = 30.0
            
        # CLAMPING LOGIC:
        # Ensure we don't show empty space past the last event
        # If the window width is larger than the entire session, just start at 0
        if width >= self.session_max_time:
            self.current_start_time = 0
        else:
            # If current start + width > max, shift start back
            if (self.current_start_time + width) > self.session_max_time:
                self.current_start_time = max(0, self.session_max_time - width)
        
        self.ax.set_xlim(self.current_start_time, self.current_start_time + width)
        self.canvas.draw()

    def scroll_next(self):
        width = self.width_var.get()
        # Propose new start time
        new_start = self.current_start_time + width
        
        # Check if new window would go entirely past data
        if new_start < self.session_max_time:
            self.current_start_time = new_start
        else:
            # Just snap to end
            self.current_start_time = max(0, self.session_max_time - width)
            
        self.update_view_limit()

    def scroll_prev(self):
        self.current_start_time = max(0, self.current_start_time - self.width_var.get())
        self.update_view_limit()

    def hover(self, event):
        if event.inaxes != self.ax:
            return

        found = False
        for coll in self.bars_collections:
            cont, ind = coll.contains(event)
            if cont:
                idx = ind['ind'][0]
                
                # Highlight
                paths = coll.get_paths()
                if idx < len(paths):
                    bbox = paths[idx].get_extents()
                    self.highlight_rect.set_xy((bbox.xmin, bbox.ymin))
                    self.highlight_rect.set_width(bbox.width)
                    self.highlight_rect.set_height(bbox.height)
                    self.highlight_rect.set_visible(True)
                
                # Update Info
                row = coll.local_data.iloc[idx]
                self.var_name.set(row['Event_Name'])
                self.var_ttl.set(str(row['TTL']))
                self.var_time.set(f"{row['Start_Time']:.3f} s")
                self.var_repeats.set(str(row['Burst_Repeats']))
                
                self.canvas.draw_idle()
                found = True
                break
        
        if not found and self.highlight_rect.get_visible():
            self.highlight_rect.set_visible(False)
            self.var_name.set("-")
            self.var_ttl.set("-")
            self.var_time.set("-")
            self.var_repeats.set("-")
            self.canvas.draw_idle()

# --- MAIN ---
if __name__ == "__main__":
    if not os.path.exists(FILE_PATH):
        print(f"CRITICAL: File not found at {FILE_PATH}")
    else:
        try:
            print("Loading Data...")
            df = pd.read_excel(FILE_PATH)
            
            # --- DATA PREP ---
            required_cols = ['Session', 'Event_Name', 'Start_Time', 'TTL']
            if not all(col in df.columns for col in required_cols):
                print(f"Error: Missing columns. Found: {df.columns.tolist()}")
            else:
                df['Visual_End'] = df['Start_Time'] + 1
                if 'Burst_Repeats' not in df.columns: df['Burst_Repeats'] = 0
                
                root = tk.Tk()
                app = EventViewerApp(root, df)
                root.mainloop()
        except Exception as e:
            print(f"Error: {e}")