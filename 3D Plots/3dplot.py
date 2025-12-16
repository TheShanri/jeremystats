import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import os
import glob
from matplotlib.patches import FancyArrowPatch
from mpl_toolkits.mplot3d import proj3d

# --- Configuration ---
CSV_FOLDER = 'csv_exports'

# 1. Dimensions & Zoom
LAYER_SPACING = 3.0      # Physical distance between layers
Z_AXIS_STRETCH = 2.5     # Visual stretch (Makes Z look taller)
R_LIMIT = 0.2            # Zoom limit (radius)

# 2. Styling
DOT_TRANSPARENCY = 0.3
ARROW_ALPHA = 0.9
ARROW_SHAFT_WIDTH = 3
ARROW_HEAD_WIDTH = 20    # Mutation scale for arrow head

# 3. Genotype Colors
GENOTYPE_COLORS = {
    'Control': 'black',
    'CTL': 'black',
    'DKO': 'blue',
    'PTEN': 'red'
}
DEFAULT_COLOR = 'gray'

# --- Custom Class for "Nice" 3D Arrows ---
class Arrow3D(FancyArrowPatch):
    def __init__(self, xs, ys, zs, *args, **kwargs):
        super().__init__((0,0), (0,0), *args, **kwargs)
        self._verts3d = xs, ys, zs

    def do_3d_projection(self, renderer=None):
        xs3d, ys3d, zs3d = self._verts3d
        xs, ys, zs = proj3d.proj_transform(xs3d, ys3d, zs3d, self.axes.M)
        self.set_positions((xs[0],ys[0]),(xs[1],ys[1]))
        return np.min(zs)

def get_color_from_filename(filename):
    name_lower = filename.lower()
    for key, color in GENOTYPE_COLORS.items():
        if key.lower() in name_lower:
            return color
    return DEFAULT_COLOR

def plot_layer_data_final(csv_path):
    # 1. Load Data
    try:
        df = pd.read_csv(csv_path)
    except Exception as e:
        print(f"Error reading {csv_path}: {e}")
        return

    filename = os.path.basename(csv_path)
    group_name = os.path.splitext(filename)[0]
    group_color = get_color_from_filename(group_name)
    
    print(f"Plotting 3D: {group_name}...")

    # 2. Setup 3D Plot
    fig = plt.figure(figsize=(12, 12)) # Slightly wider to accommodate text
    ax = fig.add_subplot(111, projection='3d')

    if 'LevelAdj' not in df.columns:
        print(f"Skipping {filename}: 'LevelAdj' missing.")
        return

    layers = sorted(df['LevelAdj'].dropna().unique())
    max_z = 0

    # --- MAIN LOOP: PLOT LAYERS ---
    for layer_idx in layers:
        # Filter Data
        layer_data = df[df['LevelAdj'] == layer_idx].dropna(subset=['r', 'mu_deg'])
        if len(layer_data) == 0:
            continue
        
        # --- CALCULATE N VALUE ---
        # If an explicit 'n' column exists (e.g. grouped data), sum it.
        # Otherwise, count the rows (raw data).
        if 'n' in layer_data.columns:
            n_val = int(layer_data['n'].sum())
        elif 'N' in layer_data.columns:
            n_val = int(layer_data['N'].sum())
        else:
            n_val = len(layer_data)

        # Update Label text for Legend
        label_text = f"L{int(layer_idx)}"

        # Coordinates
        r_all = layer_data['r'].values
        theta_all = np.deg2rad(layer_data['mu_deg'].values)
        x_all = r_all * np.cos(theta_all)
        y_all = r_all * np.sin(theta_all)
        
        # Z height
        z_height = layer_idx * LAYER_SPACING
        if z_height > max_z: max_z = z_height
        
        # --- A. Plot DOTS (Masked) ---
        mask = r_all <= R_LIMIT
        x_plot = x_all[mask]
        y_plot = y_all[mask]
        z_plot = np.full_like(x_plot, z_height)
        
        ax.scatter(x_plot, y_plot, z_plot, 
                   c=group_color, 
                   alpha=DOT_TRANSPARENCY, 
                   s=25, 
                   edgecolors='none',
                   label=label_text)
        
        # --- B. Plot ARROW ---
        if len(x_all) > 0:
            avg_x = np.mean(x_all)
            avg_y = np.mean(y_all)
            a = Arrow3D([0, avg_x], [0, avg_y], [z_height, z_height], 
                        mutation_scale=ARROW_HEAD_WIDTH, 
                        lw=ARROW_SHAFT_WIDTH, 
                        arrowstyle="-|>", 
                        color=group_color, 
                        alpha=ARROW_ALPHA)
            ax.add_artist(a)

        # --- C. LAYER GRID DETAILS ---
        # 1. Concentric Rings
        t_grid = np.linspace(0, 2*np.pi, 100)
        ring_radii = [R_LIMIT/2, R_LIMIT] 
        
        for r_val in ring_radii:
            xg = r_val * np.cos(t_grid)
            yg = r_val * np.sin(t_grid)
            zg = np.full_like(xg, z_height)
            ax.plot(xg, yg, zg, color='gray', alpha=0.2, linewidth=0.8, linestyle='-')
            
            # Radius Label (BLACK)
            ax.text(r_val, 0.02, z_height, f"{r_val:.1f}", 
                    fontsize=8, color='black', ha='center', alpha=1.0)

        # 2. Degree Lines
        deg_labels = {0: '0°', 90: '90°', 180: '180°', 270: '270°'}
        for deg, text in deg_labels.items():
            rad = np.deg2rad(deg)
            ax.plot([0, R_LIMIT * np.cos(rad)], [0, R_LIMIT * np.sin(rad)], [z_height, z_height], 
                    color='gray', alpha=0.15, linewidth=0.8)
            xt = (R_LIMIT * 1.15) * np.cos(rad)
            yt = (R_LIMIT * 1.15) * np.sin(rad)
            ax.text(xt, yt, z_height, text, 
                    fontsize=8, color='black', ha='center', va='center', alpha=1.0)

        # --- D. ADD N VALUE TEXT ---
        # Place it at the "corner" (45 degrees, just outside the boundary)
        text_offset = R_LIMIT * 1.4
        text_rad = np.deg2rad(315) # Bottom-right corner
        nx = text_offset * np.cos(text_rad)
        ny = text_offset * np.sin(text_rad)
        
        ax.text(nx, ny, z_height, f"n={n_val}", 
                color='black', fontsize=10, fontweight='bold', ha='center', va='center')

    # 3. Styling & Cleanup
    ax.set_title(f'{group_name}', fontsize=18, fontweight='bold', pad=10, color=group_color)
    ax.set_axis_off() 

    # Limits & Aspect
    ax.set_xlim(-R_LIMIT, R_LIMIT)
    ax.set_ylim(-R_LIMIT, R_LIMIT)
    ax.set_zlim(0, max_z + LAYER_SPACING)
    ax.set_box_aspect((1, 1, Z_AXIS_STRETCH))
    
    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    csv_files = glob.glob(os.path.join(CSV_FOLDER, "*.csv"))
    if not csv_files:
        print(f"No CSV files found in '{CSV_FOLDER}'")
    else:
        for csv_file in csv_files:
            plot_layer_data_final(csv_file)