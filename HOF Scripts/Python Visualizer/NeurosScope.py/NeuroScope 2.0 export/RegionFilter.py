import tkinter as tk
from PIL import Image, ImageTk, ImageDraw
import networkx as nx
import math
import io

# Force matplotlib to use a non-interactive backend to prevent GUI ghosting
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors

# ---------------------------------------------------------------------
# UTILITY
# ---------------------------------------------------------------------
def darken_color(hex_color, amount=0.6):
    try:
        c = mcolors.hex2color(hex_color)
        c = [max(0, val * amount) for val in c]
        return mcolors.to_hex(c)
    except:
        return hex_color

# ---------------------------------------------------------------------
# INTERACTIVE NETWORK FILTER MODULE
# ---------------------------------------------------------------------
class RegionFilterDialog(tk.Toplevel):
    def __init__(self, parent, all_regions, active_regions, apply_callback):
        super().__init__(parent)
        self.title("Interactive Statistical Network Filter")
        
        # Dimensions
        self.plot_size = 650
        self.geometry(f"{self.plot_size}x{self.plot_size + 100}")
        self.configure(bg="#222")
        self.resizable(False, False)
        
        # Lock focus strictly to this popup
        self.transient(parent)
        self.grab_set()

        self.all_regions = all_regions
        self.apply_callback = apply_callback
        
        # This exact order forces the physical clockwise placement 
        # starting near 12 o'clock (Right ACC).
        self.visual_order = [
            'RightACC', 'RightOFC', 'RightDHC', 'RightRSC', 'RightPER', 'RightPOR',
            'LeftPOR', 'LeftPER', 'LeftRSC', 'LeftDHC', 'LeftOFC', 'LeftACC'
        ]
        
        # Hardcoded hex colors corresponding to the visual order
        self.colors = [
            '#B972D7', '#BE8348', '#FAEE64', '#31C234', '#7ACEE4', '#CD1C38',
            '#CD1C38', '#7ACEE4', '#31C234', '#FAEE64', '#BE8348', '#B972D7'
        ]

        # Tracking dictionary: maps strict system strings to their dynamic UI data
        self.node_data = {} 
        for reg in self.all_regions:
            self.node_data[reg] = {"pos": (0, 0), "active": (reg in active_regions)}
        
        self.radius_px = 0
        
        # Boot sequence
        self.generate_network_image()
        self.setup_ui()
        self.render_overlays()

    def _format_label(self, sys_name):
        # Translates 'RightACC' -> 'ACC\nR' strictly for the visual plot
        if sys_name.startswith('Right'): return sys_name.replace('Right', '') + '\nR'
        if sys_name.startswith('Left'): return sys_name.replace('Left', '') + '\nL'
        return sys_name

    def generate_network_image(self):
        # 1. Initialize Matplotlib Engine
        dpi = 100
        fig_size = self.plot_size / dpi
        fig, ax = plt.subplots(figsize=(fig_size, fig_size), facecolor='#FAFAFA', dpi=dpi)
        
        G = nx.complete_graph(self.visual_order)
        
        # 2. Calculate Physical Geometry
        pos = {}
        for i, node in enumerate(self.visual_order):
            angle = math.radians(75 - i * 30) # 75 degrees anchors ACC slightly right of top-center
            pos[node] = (math.cos(angle), math.sin(angle))
            
        dark_colors = [darken_color(c, 0.6) for c in self.colors]
        
        # 3. Draw Network Layers
        nx.draw_networkx_edges(G, pos, alpha=0.25, edge_color='#555555', width=1.5, ax=ax)
        
        shadow_pos = {node: (x + 0.015, y - 0.015) for node, (x, y) in pos.items()}
        node_size = 2500
        nx.draw_networkx_nodes(G, shadow_pos, node_size=node_size, node_color='black', alpha=0.2, ax=ax)
        nx.draw_networkx_nodes(G, pos, node_size=node_size, node_color=self.colors, edgecolors=dark_colors, linewidths=3.0, ax=ax)
        
        labels = {node: self._format_label(node) for node in self.visual_order}
        nx.draw_networkx_labels(G, pos, labels=labels, font_size=10, font_family='sans-serif', font_weight='bold', font_color='#222222', ax=ax)
        
        plt.axis('off')
        
        # Lock limits to prevent coordinate warping
        ax.set_xlim([-1.3, 1.3])
        ax.set_ylim([-1.3, 1.3])
        
        fig.canvas.draw()
        width, height = fig.canvas.get_width_height()
        
        # 4. Extract Dynamic Pixel Coordinates
        # Matplotlib scatter node_size is points^2. Convert to UI pixels.
        self.radius_px = math.sqrt(node_size / math.pi) * (dpi / 72) * 1.2 # 20% buffer for easier clicking
        
        for node in self.visual_order:
            x_data, y_data = pos[node]
            x_px, y_px_bottom = ax.transData.transform((x_data, y_data))
            y_px_top = height - y_px_bottom # Invert Y-axis for Tkinter origin
            self.node_data[node]["pos"] = (x_px, y_px_top)
            
        # 5. Render to Memory Buffer (Bypassing Disk I/O)
        buf = io.BytesIO()
        fig.savefig(buf, format='png', facecolor=fig.get_facecolor()) # NEVER use bbox_inches='tight' here; it breaks the coordinate mapping.
        plt.close(fig)
        buf.seek(0)
        
        self.base_img = Image.open(buf)
        self.base_photo = ImageTk.PhotoImage(self.base_img)
        
        # 6. Generate Translucent Inactive Mask
        overlay_size = int(self.radius_px * 2)
        overlay_img = Image.new('RGBA', (overlay_size, overlay_size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay_img)
        draw.ellipse((0, 0, overlay_size, overlay_size), fill=(40, 40, 40, 200)) 
        self.overlay_photo = ImageTk.PhotoImage(overlay_img)

    def setup_ui(self):
        # Top Controls
        control_frame = tk.Frame(self, bg="#222")
        control_frame.pack(fill=tk.X, pady=10, padx=20)
        
        lbl = tk.Label(control_frame, text="Click Nodes to Toggle Processing State", 
                       bg="#222", fg="#fff", font=("Arial", 11, "bold"))
        lbl.pack(side=tk.LEFT)
        
        tk.Button(control_frame, text="Clear All", command=lambda: self.toggle_all(False), 
                  bg="#444", fg="#fff", bd=1).pack(side=tk.RIGHT, padx=5)
        tk.Button(control_frame, text="Select All", command=lambda: self.toggle_all(True), 
                  bg="#444", fg="#fff", bd=1).pack(side=tk.RIGHT, padx=5)
                  
        # Interactive Canvas
        self.canvas = tk.Canvas(self, width=self.plot_size, height=self.plot_size, bg="#FAFAFA", highlightthickness=0)
        self.canvas.pack()
        self.canvas.create_image(0, 0, image=self.base_photo, anchor="nw")
        
        self.canvas.bind("<Button-1>", self.on_click)
        
        # Bottom Apply Button
        btn_frame = tk.Frame(self, bg="#222")
        btn_frame.pack(fill=tk.X, side=tk.BOTTOM, pady=15)
        tk.Button(btn_frame, text="APPLY FILTER", command=self.apply_and_close,
                  bg="#00bd39", fg="white", font=("Arial", 10, "bold"), height=2).pack(fill=tk.X, padx=20)

    def on_click(self, event):
        click_x, click_y = event.x, event.y

        for node_name, data in self.node_data.items():
            node_x, node_y = data["pos"]
            distance = math.hypot(click_x - node_x, click_y - node_y)

            if distance <= self.radius_px:
                data["active"] = not data["active"]
                self.render_overlays()
                break

    def render_overlays(self):
        self.canvas.delete("overlay")
        for node_name, data in self.node_data.items():
            if not data["active"]:
                node_x, node_y = data["pos"]
                self.canvas.create_image(node_x, node_y, image=self.overlay_photo, anchor="center", tags="overlay")

    def toggle_all(self, state):
        for data in self.node_data.values():
            data["active"] = state
        self.render_overlays()

    def apply_and_close(self):
        # Harvest active nodes using their strict system names
        selected = [node for node, data in self.node_data.items() if data["active"]]
        self.apply_callback(selected)
        self.destroy()