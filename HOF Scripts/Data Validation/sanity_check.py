import os
import sys

def run_integrity_check(root_dir, output_file):
    # 1. Define what a "Complete" dataset looks like
    # We create a "Set" of strings: {"CSC1.ncs", "CSC2.ncs", ... "CSC64.ncs"}
    required_files = {f"CSC{i}.ncs" for i in range(1, 65)}
    
    passed_dirs = []
    failed_dirs = []

    if not os.path.exists(root_dir):
        print(f"Error: Path not found: {root_dir}")
        return

    print(f"Starting Integrity Check on: {root_dir}")
    print("Looking for leaf folders with CSC1.ncs -> CSC64.ncs...")
    print("-" * 60)

    # 2. Walk through every folder
    for root, dirs, files in os.walk(root_dir):
        # We only care about "Leaf" nodes (folders that have no sub-folders inside them)
        # or folders that clearly contain data (checking if any .ncs files exist)
        
        # Heuristic: If it has no sub-directories, it's a leaf. Check it.
        if len(dirs) == 0:
            current_files_set = set(files)
            
            # Check if all required files are present in the current folder
            # issubset() returns True if required_files is inside current_files_set
            if required_files.issubset(current_files_set):
                passed_dirs.append(root)
            else:
                # Calculate what is missing for the report
                missing = required_files - current_files_set
                missing_count = len(missing)
                
                # We only flag it as a "Data Fail" if it actually looks like a data folder 
                # (e.g., has at least one .ncs file) OR if it's completely empty.
                # If it's just a random empty folder, we still report it as a fail/empty.
                failed_dirs.append({
                    "path": root,
                    "missing_count": missing_count,
                    "example_missing": list(missing)[:3] # Show first 3 missing for context
                })

    # 3. Generate Report
    with open(output_file, "w", encoding="utf-8") as f:
        f.write(f"Integrity Check Report for: {root_dir}\n")
        f.write("=" * 60 + "\n\n")
        
        f.write(f"SUMMARY:\n")
        f.write(f"PASS: {len(passed_dirs)} folders\n")
        f.write(f"FAIL: {len(failed_dirs)} folders\n\n")
        
        f.write("=" * 60 + "\n")
        f.write("FAILED DIRECTORIES (Incomplete or Empty)\n")
        f.write("=" * 60 + "\n")
        
        if not failed_dirs:
            f.write("None! All leaf directories are complete.\n")
        
        for item in failed_dirs:
            f.write(f"[FAIL] {item['path']}\n")
            if item['missing_count'] == 64:
                 f.write(f"       Status: EMPTY or No CSC data found.\n")
            else:
                 f.write(f"       Missing {item['missing_count']} files.\n")
                 f.write(f"       Examples: {', '.join(item['example_missing'])}...\n")
            f.write("-" * 40 + "\n")

        f.write("\n" + "=" * 60 + "\n")
        f.write("PASSED DIRECTORIES (Data Complete)\n")
        f.write("=" * 60 + "\n")
        
        for p in passed_dirs:
            f.write(f"[OK]   {p}\n")

    print(f"\nDone! Found {len(passed_dirs)} valid and {len(failed_dirs)} invalid folders.")
    print(f"Full report saved to: {output_file}")

if __name__ == "__main__":
    target_path = r"\\netfiles03.uvm.edu\bigdata_jbarry\HOF"
    
    script_location = os.path.dirname(os.path.abspath(__file__))
    output_filename = os.path.join(script_location, "Integrity_Report.txt")
    
    run_integrity_check(target_path, output_filename)