import pandas as pd
from pymatreader import read_mat
import os
import numpy as np

def unpack_mat_structure(mat_filename):
    print(f"--- Processing {mat_filename} ---")
    
    # 1. Read the MAT file
    # pymatreader attempts to convert MATLAB Tables to Python dictionaries automatically
    try:
        data = read_mat(mat_filename)
    except Exception as e:
        print(f"CRITICAL ERROR: Could not read file. {e}")
        return

    # 2. Locate the main container
    if 'groupedData' not in data:
        print("Error: 'groupedData' key not found.")
        print(f"Available keys: {list(data.keys())}")
        return

    grouped_data = data['groupedData']
    output_dir = "unpacked_groups"
    os.makedirs(output_dir, exist_ok=True)
    
    # 3. Iterate through the dictionary keys (The "Layer of Unpacking" you needed)
    # The structure is likely: groupedData = {'CTL_CA1': {...}, 'DKO_CA1': {...}, ...}
    
    if not isinstance(grouped_data, dict):
        print(f"Warning: groupedData is not a dictionary, it is {type(grouped_data)}.")
        # Attempt to handle if it's a list/array (fallback)
        iterable = enumerate(grouped_data) if isinstance(grouped_data, list) else []
    else:
        iterable = grouped_data.items()

    print(f"\nFound {len(grouped_data)} groups/keys inside groupedData.")
    
    count = 0
    for key, content in iterable:
        # 'key' is likely the group name (e.g., "CTL_CA1")
        # 'content' is likely the data dictionary (converted from MATLAB Table)
        
        group_name = str(key)
        print(f"Unpacking: {group_name}...")

        try:
            # Check if 'content' is a dictionary (successful Table conversion)
            if isinstance(content, dict):
                # We expect keys like 'mu_deg', 'r', 'LevelAdj' inside
                df = pd.DataFrame(content)
                
                # Save to CSV
                csv_name = f"{group_name}.csv"
                save_path = os.path.join(output_dir, csv_name)
                df.to_csv(save_path, index=False)
                print(f"  -> Saved {csv_name} ({len(df)} rows)")
                count += 1
                
            else:
                # If pymatreader couldn't decode the table, it returns an object/array
                print(f"  -> SKIPPING: Data for {group_name} is not a valid dictionary. It is: {type(content)}")
                print("     (This usually means the MATLAB Table format is too complex for Python readers)")

        except Exception as e:
            print(f"  -> ERROR converting {group_name}: {e}")

    print(f"\nDone. Successfully unpacked {count} groups to '{output_dir}/'.")

if __name__ == "__main__":
    unpack_mat_structure('all_group_phase.mat')