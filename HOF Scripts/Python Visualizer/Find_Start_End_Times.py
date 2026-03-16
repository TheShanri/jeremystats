import pandas as pd
import os

# --- CONFIGURATION ---
FILE_PATH = r"D:\HOF DATA\ACTIVE DATA\All_Events_Summary.xlsx"

# --- TTL CODES ---
TTL_CODES = {
    0: "Start/End",
    126: "Session",
    124: "Click", 
    122: "Noise",
    118: "High Tone",
    110: "Low Tone",
    94: "Pellet Delivery",
    62: "Mag Poke",
    127: "End of Box Output"
}

def style_rows(row):
    """
    Pandas Styler function:
    - Unknown Codes: Gray Text, No Background
    - Bursts (Repeats): Yellow Background
    """
    status = str(row['Status'])
    
    if status == 'Unknown':
        # Gray text for Unknowns
        return ['color: #A0A0A0'] * len(row)
    
    elif status == 'Note':
        # Yellow background for Bursts/Repeats
        return ['background-color: #FFFF00'] * len(row)
        
    return [''] * len(row)

def process_events(file_path):
    if not os.path.exists(file_path):
        print(f"CRITICAL: File not found at {file_path}")
        return

    print(f"Loading data from: {file_path}...")
    
    try:
        df = pd.read_excel(file_path)
    except Exception as e:
        print(f"Error reading file: {e}")
        return

    # Standardize Column Names
    if len(df.columns) >= 5:
        mapping = {
            df.columns[1]: 'Session',
            df.columns[3]: 'Time_s',
            df.columns[4]: 'TTL'
        }
        df = df.rename(columns=mapping)
    
    # Clean Data
    df = df.dropna(subset=['Time_s', 'TTL'])
    df['Time_s'] = pd.to_numeric(df['Time_s'])
    df['TTL'] = pd.to_numeric(df['TTL'], errors='coerce').fillna(-1).astype(int)

    processed_events = []
    
    # Get unique sessions
    sessions = df['Session'].unique()
    
    for session in sessions:
        # Sort chronologically
        session_data = df[df['Session'] == session].sort_values('Time_s')
        
        # Debounce Tracker
        # Format: { TTL_Code: { 'last_time': timestamp, 'result_index': index } }
        active_trackers = {}
        
        for _, row in session_data.iterrows():
            time_val = row['Time_s']
            ttl_val = row['TTL']
            
            # --- 1. Identify ---
            if ttl_val in TTL_CODES:
                name = TTL_CODES[ttl_val]
                is_unknown = False
            else:
                name = f"Unknown ({ttl_val})"
                is_unknown = True

            # --- 2. Check for Debounce (Repeats within 1.0s) ---
            is_repeat = False
            
            if ttl_val in active_trackers:
                last_t = active_trackers[ttl_val]['last_time']
                
                # If same code appears within 1 second
                if (time_val - last_t) <= 1.0:
                    is_repeat = True
                    idx = active_trackers[ttl_val]['result_index']
                    
                    # Update the EXISTING event
                    processed_events[idx]['Repeats'] += 1
                    
                    # Only mark as 'Note' (Yellow) if it wasn't already Unknown
                    # We prioritize "Unknown" status for styling if it's unknown.
                    if processed_events[idx]['Status'] != 'Unknown':
                        processed_events[idx]['Status'] = "Note"
                        
                    processed_events[idx]['Details'] = f"Burst: {processed_events[idx]['Repeats']} repeats"
                    
                    # Update tracker time
                    active_trackers[ttl_val]['last_time'] = time_val 
                    
            # --- 3. Create New Event ---
            if not is_repeat:
                
                # Determine Status for Styling
                if is_unknown:
                    status = "Unknown"  # Will be Gray Text
                    details = "Unknown Code"
                else:
                    status = "OK"       # Will be White/Standard
                    details = ""

                new_event = {
                    'Session': session,
                    'Event_Name': name,
                    'TTL': ttl_val,
                    'Start_Time': time_val,
                    'Repeats': 0,
                    'Status': status,
                    'Details': details
                }
                
                processed_events.append(new_event)
                
                # Register tracker
                active_trackers[ttl_val] = {
                    'last_time': time_val, 
                    'result_index': len(processed_events) - 1
                }

    # --- 4. EXPORT ---
    results_df = pd.DataFrame(processed_events)
    
    if not results_df.empty:
        results_df = results_df.sort_values(by=['Session', 'Start_Time'])
        
        output_path = file_path.replace(".xlsx", "_DEBOUNCED_GRAY.xlsx")
        
        print("Applying styling (Gray for Unknowns, Yellow for Bursts)...")
        
        # Apply Styling
        styled_df = results_df.style.apply(style_rows, axis=1)
        
        try:
            styled_df.to_excel(output_path, index=False, engine='openpyxl')
            print("------------------------------------------------")
            print(f"DONE. Processed {len(results_df)} events.")
            print(f"Saved to: {output_path}")
        except PermissionError:
            print("ERROR: Close the Excel file before running the script!")
    else:
        print("No events found.")

if __name__ == "__main__":
    process_events(FILE_PATH)