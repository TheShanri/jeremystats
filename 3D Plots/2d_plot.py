import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import os
import glob

# --- Configuration ---
CSV_FOLDER = 'csv_exports'
COLORS = {
    'Control': 'black',
    'CTL': 'black',
    'DKO': 'blue',
    'PTEN': 'red'
}
DEFAULT_COLOR = 'gray'

def get_color_from_filename(filename):
    """Determines color based on the filename."""
    name_lower = filename.lower()
    for key, color in COLORS.items():
        if key.lower() in name_lower:
            return color
    return DEFAULT_COLOR

def plot_group_arrows_2d(csv_path):
    # 1. Load Data
    try:
        df = pd.read_csv(csv_path)
    except Exception as e:
        print(f"Error reading {csv_path}: {e}")
        return

    # Check columns
    if 'LevelAdj' not in df.columns or 'mu_deg' not in df.columns or 'r' not in df.columns:
        print(f"Skipping {os.path.basename(csv_path)}: Missing required columns.")
        return

    # 2. Extract Group Info
    filename = os.path.basename(csv_path)
    group_name = os.path.splitext(filename)[0]
    group_color = get_color_from_filename(group_name)
    
    # 3. Process Data by Layer
    # We want to calculate the vector mean for each layer
    layers = sorted(df['LevelAdj'].dropna().unique())
    
    vectors = []
    for layer_idx in layers:
        layer_data = df[df['LevelAdj'] == layer_idx].dropna(subset=['r', 'mu_deg'])
        
        if len(layer_data) == 0:
            continue
            
        # Convert to Cartesian to compute the correct vector mean
        r = layer_data['r'].values
        theta = np.deg2rad(layer_data['mu_deg'].values)
        
        x = r * np.cos(theta)
        y = r * np.sin(theta)
        
        mean_x = np.mean(x)
        mean_y = np.mean(y)
        
        # Convert mean vector back to Polar for plotting
        mean_r = np.sqrt(mean_x**2 + mean_y**2)
        mean_theta = np.arctan2(mean_y, mean_x)
        
        vectors.append({
            'layer': int(layer_idx),
            'theta': mean_theta,
            'r': mean_r
        })

    if not vectors:
        print(f"No valid data found for {group_name}")
        return

    print(f"Plotting 2D Arrows for: {group_name}")

    # 4. Setup 2D Polar Plot
    fig, ax = plt.subplots(figsize=(8, 8), subplot_kw={'projection': 'polar'})
    
    # Set the direction of 0 degrees (Standard is East/Right)
    ax.set_theta_zero_location('E') 
    ax.set_theta_direction(1) # Counter-Clockwise

    # 5. Draw Arrows
    
    # --- CHANGE 1: FORCE R MAX TO 1.0 ---
    ax.set_ylim(0, 1.0) 

    for v in vectors:
        # Calculate Degree for display (0-360)
        deg_val = np.degrees(v['theta']) % 360
        
        # Plot the arrow
        ax.annotate(
            '',  # No text in annotation, just arrow
            xy=(v['theta'], v['r']),  # Tip
            xytext=(0, 0),            # Tail
            arrowprops=dict(
                facecolor=group_color, 
                edgecolor=group_color,
                width=3,       
                headwidth=10,  
                alpha=0.8
            )
        )
        
        # --- CHANGE 2: LABEL WITH DEGREE ---
        # Label text includes Layer and Degree
        label_text = f"L{v['layer']}\n{deg_val:.0f}°"
        
        # Position label slightly beyond the arrow tip
        # We add a small offset to 'r' to push the text out
        text_r = v['r'] + 0.08
        
        ax.text(
            v['theta'], text_r, 
            label_text, 
            color=group_color, 
            fontsize=9, 
            fontweight='bold',
            ha='center', va='center'
        )

    # 6. Styling
    ax.set_title(f"Average Vectors: {group_name}", fontsize=15, fontweight='bold', pad=20)
    
    # Optional: Clean up grid lines
    # ax.set_rticks([0.2, 0.4, 0.6, 0.8, 1.0]) 
    
    plt.tight_layout()
    plt.show()

# --- Main Execution ---
if __name__ == "__main__":
    csv_files = glob.glob(os.path.join(CSV_FOLDER, "*.csv"))
    
    if not csv_files:
        print(f"No CSV files found in '{CSV_FOLDER}'")
    else:
        for csv_file in csv_files:
            plot_group_arrows_2d(csv_file)