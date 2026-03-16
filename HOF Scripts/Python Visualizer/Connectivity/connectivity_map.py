import networkx as nx
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import math
import json

# Node definition corresponding to your layout
nodes = [
    'ACC\nR', 'OFC\nR', 'DHC\nR', 'RSC\nR', 'PER\nR', 'POR\nR',
    'POR\nL', 'PER\nL', 'RSC\nL', 'DHC\nL', 'OFC\nL', 'ACC\nL'
]

# Hex colors matched to your legend
colors = [
    '#B972D7', '#BE8348', '#FAEE64', '#31C234', '#7ACEE4', '#CD1C38',
    '#CD1C38', '#7ACEE4', '#31C234', '#FAEE64', '#BE8348', '#B972D7'
]

# Function to darken hex colors
def darken_color(hex_color, amount=0.6):
    try:
        c = mcolors.hex2color(hex_color)
        c = [max(0, val * amount) for val in c]
        return mcolors.to_hex(c)
    except:
        return hex_color

# Apply darkening function for edge colors
dark_colors = [darken_color(c, 0.6) for c in colors]

# Create fully connected graph
G = nx.complete_graph(nodes)

# Calculate exact circular positions
pos = {}
for i, node in enumerate(nodes):
    angle = math.radians(75 - i * 30)
    pos[node] = (math.cos(angle), math.sin(angle))

# Initialize the plot with a slightly off-white background
fig, ax = plt.subplots(figsize=(10, 10), facecolor='#FAFAFA')

# Draw slightly thicker, darker edges
nx.draw_networkx_edges(G, pos, alpha=0.25, edge_color='#555555', width=1.5, ax=ax)

# Draw node shadows for a dimensional aesthetic
shadow_pos = {node: (x + 0.015, y - 0.015) for node, (x, y) in pos.items()}
nx.draw_networkx_nodes(G, shadow_pos, node_size=4000, node_color='black', alpha=0.2, ax=ax)

# Draw primary nodes with darker borders
nx.draw_networkx_nodes(G, pos, node_size=4000, node_color=colors, edgecolors=dark_colors, linewidths=4.0, ax=ax)

# Draw bold labels
nx.draw_networkx_labels(G, pos, font_size=12, font_family='sans-serif', font_weight='bold', font_color='#222222', ax=ax)

# Clean up axes
plt.axis('off')
plt.tight_layout()

# Save figure to PNG
fig.savefig('connectivity_matrix.png', dpi=300, bbox_inches='tight', facecolor=fig.get_facecolor())

# Calculate pixel coordinates for the log file
fig.canvas.draw()
dpi = fig.dpi

# Matplotlib scatter node_size is Area in points^2
# Area = pi * r_points^2  --> r_points = sqrt(Area / pi)
# r_pixels = r_points * (dpi / 72)
radius_px = math.sqrt(4000 / math.pi) * (dpi / 72)

log_data = []
width, height = fig.canvas.get_width_height()

for node in nodes:
    # transData transforms data coords to display coords (pixels, bottom-left origin)
    x_data, y_data = pos[node]
    x_px, y_px_bottom = ax.transData.transform((x_data, y_data))
    
    # UI coordinates typically use top-left origin, so we calculate that as well
    y_px_top = height - y_px_bottom
    
    log_data.append({
        'node': node.replace('\n', '_'),
        'center_x_px': round(x_px, 2),
        'center_y_px_ui': round(y_px_top, 2),
        'center_y_px_plot': round(y_px_bottom, 2),
        'radius_px': round(radius_px, 2)
    })

# Write to log file
with open('node_coordinates.log', 'w') as f:
    f.write(f"Image Dimensions: {width}x{height} pixels (DPI: {dpi})\n")
    f.write("=" * 50 + "\n\n")
    for entry in log_data:
        f.write(f"Node: {entry['node']}\n")
        f.write(f"  Center X (px): {entry['center_x_px']}\n")
        f.write(f"  Center Y (px, Top-Left Origin / UI Mapping): {entry['center_y_px_ui']}\n")
        f.write(f"  Center Y (px, Bottom-Left Origin / Plot Mapping): {entry['center_y_px_plot']}\n")
        f.write(f"  Radius (px): {entry['radius_px']}\n")
        f.write("-" * 50 + "\n")

print("Files saved successfully.")