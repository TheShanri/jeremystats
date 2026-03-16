import os
import json
import sys

def build_json_tree(path):
    """
    Recursively builds a clean nested dictionary with 'name' and 'subdir'.
    """
    # Get the folder or file name
    name = os.path.basename(path)
    if not name: 
        name = os.path.basename(os.path.dirname(path))

    # Initialize the node
    node = { "name": name }

    # If it's a directory, populate 'subdir'
    if os.path.isdir(path):
        subdir = []
        try:
            with os.scandir(path) as it:
                # Sort entries: folders first, then files, alphabetic within
                entries = sorted(list(it), key=lambda e: (not e.is_dir(), e.name.lower()))
                
                for entry in entries:
                    if entry.is_dir():
                        # Recursively call function for subdirectories
                        subdir.append(build_json_tree(entry.path))
                    else:
                        # Add files as simple objects
                        subdir.append({ "name": entry.name })
            
            # Only add the 'subdir' key if the folder is not empty
            if subdir:
                node["subdir"] = subdir
                
        except PermissionError:
            node["error"] = "Access Denied"
    
    return node

if __name__ == "__main__":
    # Hardcoded network path
    target_path = r"\\netfiles03.uvm.edu\bigdata_jbarry\HOF"
    
    # Verify access
    if not os.path.exists(target_path):
        print(f"Error: Cannot access {target_path}")
        print("Check your VPN or network connection.")
        sys.exit(1)

    # Save location (same folder as script)
    script_location = os.path.dirname(os.path.abspath(__file__))
    output_filename = os.path.join(script_location, "HOF_File_Tree.json")

    print(f"Scanning {target_path}...")
    
    tree_data = build_json_tree(target_path)

    try:
        with open(output_filename, "w", encoding="utf-8") as f:
            json.dump(tree_data, f, indent=4)
        print(f"Success! JSON saved to: {output_filename}")
    except Exception as e:
        print(f"Error saving file: {e}")