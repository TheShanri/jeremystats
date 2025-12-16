import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import os
import glob

# --- Configuration ---
CSV_FOLDER = 'csv_exports'

# Visualization Settings
DOT_TRANSPARENCY = 0.4   # 0.0 to 1.0
ARROW_TRANSPARENCY = 0.9 # 0.0 to 1.0
R_LIMIT = 0.2            # <--- CUT OFF GRAPH AT 0.2r (Zoom Level)

# Layer Colors
LAYER_COLORS = {
    1: 'tab:blue',   
    2: 'tab:orange', 
    3: 'tab:green',  
    4: 'tab:red'     
}
DEFAULT_LAYER_COLOR = 'gray'

def plot_group_polar(csv_path):
    # 1. Load Data
    try:
        df = pd.read_csv(csv_path)
    except Exception as e:
        print(f"Error reading {csv_path}: {e}")
        return

    if 'LevelAdj' not in df.columns or 'mu_deg' not in df.columns or 'r' not in df.columns:
        print(f"Skipping {os.path.basename(csv_path)}: Missing columns.")
        return

    # 2. Setup File Info
    filename = os.path.basename(csv_path)
    group_name = os.path.splitext(filename)[0]
    
    # 3. Setup Polar Plot
    fig, ax = plt.subplots(figsize=(8, 8), subplot_kw={'projection': 'polar'})
    ax.set_theta_zero_location('E') # 0 at East
    ax.set_theta_direction(1)       # Counter-clockwise

    print(f"Plotting {group_name} (Cutoff: {R_LIMIT}r)...")
    
    # 4. Iterate Through Layers
    layers = sorted(df['LevelAdj'].dropna().unique())

    for layer_idx in layers:
        # Filter Data
        layer_data = df[df['LevelAdj'] == layer_idx].dropna(subset=['r', 'mu_deg'])
        if len(layer_data) == 0:
            continue
            
        c = LAYER_COLORS.get(int(layer_idx), DEFAULT_LAYER_COLOR)
        
        # Prepare Coordinates
        r_vals = layer_data['r'].values
        theta_vals = np.deg2rad(layer_data['mu_deg'].values)
        
        # --- A. Plot DOTS (Scatter) ---
        # Note: Dots > R_LIMIT will be clipped by set_ylim later
        ax.scatter(theta_vals, r_vals, 
                   c=c, 
                   alpha=DOT_TRANSPARENCY, 
                   s=25,               
                   edgecolors='none', 
                   label=f'Layer {int(layer_idx)}'
        )

        # --- B. Plot ARROW (Average Vector) ---
        # 1. Cartesian Conversion for Mean
        x_cart = r_vals * np.cos(theta_vals)
        y_cart = r_vals * np.sin(theta_vals)
        
        mean_x = np.mean(x_cart)
        mean_y = np.mean(y_cart)
        
        # 2. Polar Conversion for Plotting
        mean_r = np.sqrt(mean_x**2 + mean_y**2)
        mean_theta = np.arctan2(mean_y, mean_x)
        
        # 3. Draw Arrow
        ax.annotate(
            '', 
            xy=(mean_theta, mean_r), 
            xytext=(0, 0),
            arrowprops=dict(
                facecolor=c, 
                edgecolor='black',
                linewidth=1,
                width=5,        # Thicker shaft
                headwidth=15,   # Larger head
                alpha=ARROW_TRANSPARENCY
            )
        )

    # 5. Styling
    ax.set_title(f"Group: {group_name}", fontsize=16, fontweight='bold', pad=20)
    
    # --- CRITICAL: Set the Zoom / Cutoff ---
    ax.set_ylim(0, R_LIMIT)  # Cuts off everything beyond 0.2
    
    # Optional: Fix the radial grid labels to be readable in this small range
    ax.set_yticks(np.linspace(0, R_LIMIT, 5)) 
    
    # Legend
    ax.legend(loc='upper right', bbox_to_anchor=(1.3, 1.1))
    
    plt.tight_layout()
    plt.show()

# --- Main Execution ---
if __name__ == "__main__":
    csv_files = glob.glob(os.path.join(CSV_FOLDER, "*.csv"))
    
    if not csv_files:
        print(f"No CSV files found in '{CSV_FOLDER}'")
    else:
        for csv_file in csv_files:
            plot_group_polar(csv_file)