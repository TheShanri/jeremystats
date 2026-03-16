import pandas as pd
import matplotlib.pyplot as plt

# Hardcoded file path
file_path = r"D:\HOF DATA\ACTIVE DATA\Combo_Events_Timeline.xlsx"

# Load the data
df = pd.read_excel(file_path)

# Map TTL values to standardized event names
ttl_map = {
    126: "126 Session",
    124: "124 Click",
    122: "122 Noise",
    118: "118 High tone",
    110: "110 Low Tone",
    94:  "94 Pellet Delivery",
    62:  "62 Mag Poke",
    127: "127 End of Box Output",
    0:   "0 Start/End",
    200: "200 Click_Noise",
    201: "201 HighTone_LowTone"
}

# Hardcode specific colors for each event label to enforce consistency
color_map = {
    "118 High tone": "green",
    "110 Low Tone": "red",
    "124 Click": "blue",
    "122 Noise": "orange",
    "201 HighTone_LowTone": "cyan",   # Updated
    "200 Click_Noise": "purple",      # Updated
    "126 Session": "black",
    "94 Pellet Delivery": "lime",
    "62 Mag Poke": "magenta",
    "127 End of Box Output": "brown",
    "0 Start/End": "gray",
    "Unknown": "pink"
}

# Apply mapping
df["Event_Label"] = df["TTL"].apply(lambda x: ttl_map.get(x, "Unknown"))

# Filter out sessions with 2 or fewer events
session_counts = df["Session"].value_counts()
valid_sessions = session_counts[session_counts > 2].index
df = df[df["Session"].isin(valid_sessions)]

# Determine all remaining sessions, inject the missing session, and sort alphabetically
missing_session = "J2_PRECON1_SP_00000 [MISSING DATA]"
sessions = sorted(list(df["Session"].dropna().unique()))

if missing_session not in sessions:
    sessions.append(missing_session)
    sessions = sorted(sessions)

# Map each session to a Y-coordinate
session_to_y = {session: i for i, session in enumerate(sessions)}
df["y_val"] = df["Session"].map(session_to_y)

# Get counts for secondary axis
counts = df["Session"].value_counts().to_dict()
counts[missing_session] = 0

# Initialize the plot
fig, ax1 = plt.subplots(figsize=(14, max(6, len(sessions) * 0.5)))

# Plot each event type with fixed colors
labels_present = df["Event_Label"].unique()
for label in labels_present:
    subset = df[df["Event_Label"] == label]
    ax1.scatter(
        subset["Start_Time"], 
        subset["y_val"], 
        label=label, 
        color=color_map.get(label, "pink"),
        alpha=0.8, 
        edgecolors='k',
        s=50
    )

# Formatting primary Y-axis
ax1.set_yticks(range(len(sessions)))
ax1.set_yticklabels(sessions)
ax1.set_xlabel("Start Time (s)")
ax1.set_ylabel("Session")

# Apply color-coding and bolding to Y-axis labels
for tick in ax1.get_yticklabels():
    text = tick.get_text()
    if text == missing_session:
        tick.set_color('red')
        tick.set_fontweight('bold')
    elif text.startswith('J1'):
        tick.set_color('blue')
        tick.set_fontweight('bold')
    elif text.startswith('J2'):
        tick.set_color('green')
        tick.set_fontweight('bold')

# Formatting secondary Y-axis for total event counts
ax2 = ax1.twinx()
ax2.set_ylim(ax1.get_ylim())
ax2.set_yticks(range(len(sessions)))
ax2.set_yticklabels([f"Total: {counts.get(s, 0)}" for s in sessions])
ax2.set_ylabel("Event Count")

ax1.set_title("Combo Events over Time per Session")

# Place legend outside the plot area
ax1.legend(title="Event Types", bbox_to_anchor=(1.15, 1), loc='upper left')

plt.tight_layout()
plt.show()