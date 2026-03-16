import os
import glob
import pandas as pd

# --- CONFIGURATION ---
TARGET_DIR = r"D:\HOF DATA\ACTIVE DATA\PYTHON_UI_DATA\Combo_Events"
OUTPUT_FILENAME = "Ultra_Master_Log.csv"

def compile_master_log(directory, output_file):
    print(f"Scanning directory: {directory}")
    
    if not os.path.exists(directory):
        print(f"CRITICAL: Directory does not exist: {directory}")
        return

    # Find all CSV files that match the log pattern
    # We use a wildcard to ensure we only grab the individual logs
    search_pattern = os.path.join(directory, "Master_Log_*.csv")
    csv_files = glob.glob(search_pattern)

    if not csv_files:
        print("No CSV files found matching 'Master_Log_*.csv'.")
        return

    print(f"Found {len(csv_files)} log files. Concatenating...")

    df_list = []
    failed_files = []

    for file in csv_files:
        try:
            # Read each CSV. We assume standard comma separation and header presence.
            df = pd.read_csv(file)
            df_list.append(df)
        except Exception as e:
            failed_files.append((os.path.basename(file), str(e)))

    if not df_list:
        print("No data could be extracted from the files.")
        return

    # Concatenate all dataframes into one
    ultra_df = pd.concat(df_list, ignore_index=True)

    # Sort the final log chronologically by Timestamp if available
    if 'Timestamp' in ultra_df.columns:
        ultra_df['Timestamp'] = pd.to_datetime(ultra_df['Timestamp'], errors='ignore')
        ultra_df = ultra_df.sort_values(by='Timestamp')

    # Define the output path
    output_path = os.path.join(directory, output_file)

    # Save to CSV
    try:
        ultra_df.to_csv(output_path, index=False)
        print("=======================================================")
        print(f"SUCCESS: Compiled {len(df_list)} files.")
        print(f"Total rows: {len(ultra_df)}")
        print(f"Saved Ultra Master Log to: {output_path}")
        print("=======================================================")
    except PermissionError:
        print(f"ERROR: Permission denied. Close '{output_file}' if it is open in Excel and run again.")

    # Report any failures
    if failed_files:
        print("\nWARNING: The following files failed to process:")
        for fname, err in failed_files:
            print(f"  - {fname}: {err}")

if __name__ == "__main__":
    compile_master_log(TARGET_DIR, OUTPUT_FILENAME)