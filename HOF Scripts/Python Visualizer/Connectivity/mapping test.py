import tkinter as tk
from PIL import Image, ImageTk, ImageDraw
import math
import sys

# Define asset path
IMAGE_PATH = r"C:\Users\Z390\Desktop\jeremystats\HOF Scripts\Python Visualizer\Connectivity\connectivity_matrix.png"

# Setup dynamic scaling
SCALE_FACTOR = 0.7  # Change this to 0.5 for half-size, 0.8 for 80% size, etc.
ORIGINAL_SIZE = 1000
ORIGINAL_RADIUS = 49.56

WINDOW_SIZE = int(ORIGINAL_SIZE * SCALE_FACTOR)
RADIUS = ORIGINAL_RADIUS * SCALE_FACTOR

# Map UI coordinates and apply scale
RAW_NODES = {
    "ACC_R": (607.4, 99.17),
    "OFC_R": (793.43, 206.57),
    "DHC_R": (900.83, 392.6),
    "RSC_R": (900.83, 607.4),
    "PER_R": (793.43, 793.43),
    "POR_R": (607.4, 900.83),
    "POR_L": (392.6, 900.83),
    "PER_L": (206.57, 793.43),
    "RSC_L": (99.17, 607.4),
    "DHC_L": (99.17, 392.6),
    "OFC_L": (206.57, 206.57),
    "ACC_L": (392.6, 99.17)
}

# Build final scaled node dictionary
NODES = {name: {"pos": (x * SCALE_FACTOR, y * SCALE_FACTOR), "active": True} 
         for name, (x, y) in RAW_NODES.items()}

class ConnectivityApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Connectivity Matrix UI")
        self.root.geometry(f"{WINDOW_SIZE}x{WINDOW_SIZE}")
        self.root.resizable(False, False)

        # Setup Canvas
        self.canvas = tk.Canvas(root, width=WINDOW_SIZE, height=WINDOW_SIZE, highlightthickness=0)
        self.canvas.pack()

        # Load and scale base image
        try:
            raw_img = Image.open(IMAGE_PATH)
            self.base_img = raw_img.resize((WINDOW_SIZE, WINDOW_SIZE), Image.Resampling.LANCZOS)
            self.base_photo = ImageTk.PhotoImage(self.base_img)
        except Exception as e:
            print(f"Error loading image: {e}")
            sys.exit(1)

        self.canvas.create_image(0, 0, image=self.base_photo, anchor="nw")

        # Generate scaled translucent gray overlay
        overlay_size = int(RADIUS * 2)
        overlay_img = Image.new('RGBA', (overlay_size, overlay_size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay_img)
        draw.ellipse((0, 0, overlay_size, overlay_size), fill=(100, 100, 100, 200))
        self.overlay_photo = ImageTk.PhotoImage(overlay_img)

        # Bind Click Event
        self.canvas.bind("<Button-1>", self.on_click)

    def on_click(self, event):
        click_x, click_y = event.x, event.y

        # Detect collisions
        for node_name, data in NODES.items():
            node_x, node_y = data["pos"]
            distance = math.hypot(click_x - node_x, click_y - node_y)

            if distance <= RADIUS:
                # Toggle state and render
                data["active"] = not data["active"]
                self.render_overlays()
                break

    def render_overlays(self):
        # Clear existing overlays
        self.canvas.delete("overlay")

        # Draw overlays for inactive nodes
        for node_name, data in NODES.items():
            if not data["active"]:
                node_x, node_y = data["pos"]
                self.canvas.create_image(node_x, node_y, image=self.overlay_photo, anchor="center", tags="overlay")

if __name__ == "__main__":
    root = tk.Tk()
    app = ConnectivityApp(root)
    root.mainloop()