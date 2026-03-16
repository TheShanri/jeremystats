import os
import pandas as pd

# --- CONFIGURATION ---
INPUT_FILE = r"D:\HOF DATA\ACTIVE DATA\All_Events_Summary_Global_Timeline_Input.xlsx"

# Dynamically set the output file to be in the same directory as the input file
OUTPUT_FILE = os.path.join(os.path.dirname(INPUT_FILE), "Combo_Events_Timeline.xlsx")

MAX_GAP_SECONDS = 11.0

# Custom TTLs for the new combined events (ensure these don't overlap with existing hardware TTLs)
COMBO_TTLS = {
    'Click_Noise': 200,
    'HighTone_LowTone': 201
}

def generate_combo_spreadsheet():
    print(f"Reading input data from: {INPUT_FILE}")
    try:
        df = pd.read_excel(INPUT_FILE)
    except FileNotFoundError:
        print(f"ERROR: Could not find {INPUT_FILE}. Make sure the path is correct.")
        return
    except Exception as e:
        print(f"ERROR reading file: {e}")
        return

    # Clean column names just in case
    df.columns = df.columns.str.strip()

    # Ensure Start_Time is numeric and sort chronologically per session
    df['Start_Time'] = pd.to_numeric(df['Start_Time'], errors='coerce')
    df = df.dropna(subset=['Start_Time'])
    df = df.sort_values(by=['Session', 'Start_Time']).reset_index(drop=True)

    combo_records = []
    
    # Process each session individually
    sessions = df['Session'].unique()
    for sess in sessions:
        sess_data = df[df['Session'] == sess].to_dict('records')
        
        skip_indices = set()
        
        for i in range(len(sess_data)):
            if i in skip_indices:
                continue
                
            ev1 = sess_data[i]
            name1 = str(ev1['Event_Name']).strip()
            t1 = ev1['Start_Time']
            
            target_name2 = None
            combo_name = None
            
            if name1 == 'Click':
                target_name2 = 'Noise'
                combo_name = 'Click_Noise'
            elif name1 == 'High Tone':
                target_name2 = 'Low Tone'
                combo_name = 'HighTone_LowTone'
                
            if target_name2:
                # Scan ahead for the paired event
                for j in range(i + 1, len(sess_data)):
                    ev2 = sess_data[j]
                    name2 = str(ev2['Event_Name']).strip()
                    t2 = ev2['Start_Time']
                    
                    if t2 - t1 > MAX_GAP_SECONDS:
                        break # Exceeded the 11-second window
                        
                    if name2 == target_name2 and j not in skip_indices:
                        # Valid combo found
                        midpoint = t1 + ((t2 - t1) / 2.0)
                        
                        combo_records.append({
                            'Session': sess,
                            'Event_Name': combo_name,
                            'TTL': COMBO_TTLS[combo_name],
                            'Start_Time': midpoint,
                            'Gap_to_Next_s': '', # Blank out auxiliary columns
                            'Burst_Repeats': ''
                        })
                        
                        skip_indices.add(i)
                        skip_indices.add(j)
                        break

    if not combo_records:
        print("No valid combos found within the 11-second window.")
        return

    combo_df = pd.DataFrame(combo_records)
    
    # Sort the final output
    combo_df = combo_df.sort_values(by=['Session', 'Start_Time'])
    
    try:
        combo_df.to_excel(OUTPUT_FILE, index=False)
        print("=======================================================")
        print(f"SUCCESS: Generated {len(combo_df)} combo events.")
        print(f"Saved to: {OUTPUT_FILE}")
        print("=======================================================")
    except Exception as e:
        print(f"ERROR saving file: {e}")

if __name__ == "__main__":
    generate_combo_spreadsheet()