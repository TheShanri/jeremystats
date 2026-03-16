import pandas as pd
import os

# --- CONFIGURATION ---
INPUT_FILE = r"D:\HOF DATA\ACTIVE DATA\All_Events_Summary_DEBOUNCED.xlsx"
# Note: I'm using the _DEBOUNCED.xlsx file we just made. 
# If you specifically want to read the _GRAY version, change the line above.

def process_gaps(file_path):
    if not os.path.exists(file_path):
        print(f"CRITICAL: File not found at {file_path}")
        print("Please run the previous 'Debounce' script first to generate this file.")
        return

    print(f"Loading data from: {file_path}...")
    
    try:
        df = pd.read_excel(file_path)
    except Exception as e:
        print(f"Error reading file: {e}")
        return

    # --- 1. FILTERING ---
    print(f"Initial Row Count: {len(df)}")

    # A. Remove Unknowns
    # We check if 'Event_Name' contains "Unknown"
    df = df[~df['Event_Name'].astype(str).str.contains("Unknown", case=False, na=False)]
    
    # B. Remove TTL 126 (Session)
    df = df[df['TTL'] != 126]
    
    print(f"Row Count after Filtering: {len(df)}")

    # --- 2. FORMATTING ---
    
    # A. Simplify Burst Repeats
    # Extract just the number if it's a string like "Burst: 5 repeats", otherwise keep number
    def clean_repeats(val):
        str_val = str(val)
        if "Burst:" in str_val:
            # Extract number between 'Burst: ' and ' repeats'
            return int(''.join(filter(str.isdigit, str_val)))
        return val # Likely 0 or already a number

    if 'Details' in df.columns:
        df['Burst_Repeats'] = df['Details'].apply(clean_repeats)
    else:
        df['Burst_Repeats'] = 0
        
    # --- 3. CALCULATE GAPS ---
    # We must calculate gaps per session to avoid negative gaps between different files
    
    df = df.sort_values(by=['Session', 'Start_Time'])
    
    # Calculate difference between Current Start Time and PREVIOUS Start Time?
    # Or Current Event to NEXT Event? User asked "gap between an event and the next event"
    # This usually means: Next_Start - Current_Start (Inter-Event Interval)
    
    # Shift(-1) gets the next row's value
    df['Next_Event_Time'] = df.groupby('Session')['Start_Time'].shift(-1)
    df['Gap_to_Next_s'] = df['Next_Event_Time'] - df['Start_Time']
    
    # Clean up the last event of each session (Gap will be NaN)
    df['Gap_to_Next_s'] = df['Gap_to_Next_s'].fillna(0)

    # --- 4. EXPORT ---
    # Select and Reorder Columns
    # Assuming 'RatID' might be in Col A if it was preserved. 
    # If not, we rely on 'Session'.
    
    cols_to_keep = ['Session', 'Event_Name', 'TTL', 'Start_Time', 'Gap_to_Next_s', 'Burst_Repeats']
    
    # If RatID exists in original, keep it
    if 'RatID' in df.columns:
        cols_to_keep.insert(0, 'RatID')
        
    final_df = df[cols_to_keep].copy()
    
    # Save
    output_path = file_path.replace(".xlsx", "_ANALYZED.xlsx")
    
    try:
        final_df.to_excel(output_path, index=False)
        print("------------------------------------------------")
        print(f"DONE. Saved analysis to: {output_path}")
        print("Filtered out Unknowns and TTL 126.")
        print("Calculated 'Gap_to_Next_s' for all events.")
    except PermissionError:
        print("ERROR: Close the Excel file before running the script!")

if __name__ == "__main__":
    process_gaps(INPUT_FILE)