import os
import json
import sys

def build_tree_data(path):
    name = os.path.basename(path)
    if not name: 
        name = os.path.basename(os.path.dirname(path))

    node = { "name": name }

    if os.path.isdir(path):
        children = []
        try:
            with os.scandir(path) as it:
                # Sort: Folders first, then files
                entries = sorted(list(it), key=lambda e: (not e.is_dir(), e.name.lower()))
                for entry in entries:
                    if entry.is_dir():
                        children.append(build_tree_data(entry.path))
                    else:
                        children.append({ "name": entry.name, "value": 1 })
            
            if children:
                node["children"] = children
        except PermissionError:
            node["name"] += " (Access Denied)"
            # Add a dummy child so it looks expandable even if empty
            node["children"] = [{"name": "No Access"}]
    
    return node

def generate_html(tree_data, output_file):
    json_data = json.dumps(tree_data)

    html_template = f"""
    <!DOCTYPE html>
    <html style="height: 100%">
    <head>
        <meta charset="utf-8">
        <title>HOF Horizontal Tree</title>
        <script src="https://cdn.jsdelivr.net/npm/echarts@5.4.3/dist/echarts.min.js"></script>
    </head>
    <body style="height: 100%; margin: 0; background-color: #fff;">
        <div id="container" style="height: 100%"></div>
        <script type="text/javascript">
            var dom = document.getElementById('container');
            
            // KEY FIX: We enforce 'svg' renderer here to stop ghosting/glitches
            var myChart = echarts.init(dom, null, {{ renderer: 'svg' }});
            
            var data = {json_data};

            var option = {{
                tooltip: {{
                    trigger: 'item',
                    triggerOn: 'mousemove'
                }},
                series: [
                    {{
                        type: 'tree',
                        data: [data],

                        top: '1%',
                        left: '7%',
                        bottom: '1%',
                        right: '20%',

                        symbolSize: 10,
                        
                        // This makes it horizontal (Left to Right)
                        orient: 'LR',

                        label: {{
                            position: 'left',
                            verticalAlign: 'middle',
                            align: 'right',
                            fontSize: 14
                        }},

                        leaves: {{
                            label: {{
                                position: 'right',
                                verticalAlign: 'middle',
                                align: 'left'
                            }}
                        }},

                        emphasis: {{
                            focus: 'descendant'
                        }},
                        
                        // How many levels to show initially (prevents lag on massive trees)
                        initialTreeDepth: 2, 

                        expandAndCollapse: true,
                        animationDuration: 550,
                        animationDurationUpdate: 750
                    }}
                ]
            }};

            myChart.setOption(option);
            window.addEventListener('resize', myChart.resize);
        </script>
    </body>
    </html>
    """
    
    with open(output_file, "w", encoding="utf-8") as f:
        f.write(html_template)

if __name__ == "__main__":
    target_path = r"\\netfiles03.uvm.edu\bigdata_jbarry\HOF"
    
    script_location = os.path.dirname(os.path.abspath(__file__))
    output_filename = os.path.join(script_location, "HOF_Horizontal_Tree.html")

    if not os.path.exists(target_path):
        print(f"Error: Cannot access {target_path}")
    else:
        print(f"Scanning {target_path}...")
        tree_data = build_tree_data(target_path)
        
        print("Generating Horizontal SVG Tree...")
        generate_html(tree_data, output_filename)
        print(f"Done! Open: {output_filename}")