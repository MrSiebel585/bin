#!/usr/init/env python3
#!/usr/bin/env python3
import os
import sys
import json
import ast
import glob
from datetime import datetime

OFFENSIVE_ROOT = os.getenv("OFFENSIVE_ROOT", "/opt/offensive")
REGISTRY_PATH = os.path.join(OFFENSIVE_ROOT, "registry.json")

SCAN_TARGETS = [
    os.getenv("OFFENSIVE_BIN_DIR", os.path.join(OFFENSIVE_ROOT, "bin")),
    os.getenv("OFFENSIVE_SCRIPTS_DIR", os.path.join(OFFENSIVE_ROOT, "scripts")),
    os.path.join(OFFENSIVE_ROOT, "python")
]

def extract_python_metadata(filepath):
    """Extracts docstrings, functions, and imports from a Python script."""
    meta = {"type": "python", "functions": [], "docstring": "", "imports": []}
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        tree = ast.parse(content)
        meta["docstring"] = ast.get_docstring(tree) or "No docstring provided."
        
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                meta["functions"].append(node.name)
            elif isinstance(node, ast.Import):
                for alias in node.names:
                    meta["imports"].append(alias.name)
            elif isinstance(node, ast.ImportFrom):
                if node.module:
                    meta["imports"].append(node.module)
    except Exception as e:
        meta["error"] = str(e)
    return meta

def extract_shell_metadata(filepath):
    """Extracts header comments and function declarations from a shell script."""
    meta = {"type": "shell", "comments": [], "functions": []}
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
            
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("#") and len(stripped) > 1:
                meta["comments"].append(stripped[1:].strip())
            elif "(" in stripped and "()" in stripped:
                func_name = stripped.split("()")[0].strip()
                meta["functions"].append(func_name)
    except Exception as e:
        meta["error"] = str(e)
    return meta

def build_registry():
    """Scans all target directories and builds the active capability registry."""
    registry = {
        "last_updated": datetime.now().isoformat(),
        "total_tools": 0,
        "inventory": {}
    }
    
    for base_dir in SCAN_TARGETS:
        if not os.path.exists(base_dir):
            continue
        for root, _, files in os.walk(base_dir):
            for file in files:
                filepath = os.path.join(root, file)
                if file.endswith(".py"):
                    registry["inventory"][file] = {
                        "path": filepath,
                        **extract_python_metadata(filepath)
                    }
                    registry["total_tools"] += 1
                elif file.endswith(".sh"):
                    registry["inventory"][file] = {
                        "path": filepath,
                        **extract_shell_metadata(filepath)
                    }
                    registry["total_tools"] += 1
                    
    with open(REGISTRY_PATH, "w", encoding="utf-8") as f:
        json.dump(registry, f, indent=2)
        
    print(f"[+] Registry built successfully: {registry['total_tools']} tools indexed at {REGISTRY_PATH}")

def query_registry(search_term=None):
    """Queries or displays the indexed tool inventory."""
    if not os.path.exists(REGISTRY_PATH):
        build_registry()
        
    with open(REGISTRY_PATH, "r", encoding="utf-8") as f:
        registry = json.load(f)
        
    if not search_term:
        print(f"\n==========================================")
        print(f" Omniscient System Inventory ({registry['total_tools']} tools)")
        print(f"==========================================")
        for name, data in registry["inventory"].items():
            print(f"- {name} [{data['type'].upper()}] -> {data['path']}")
        print("==========================================")
    else:
        print(f"\n[*] Searching inventory for: '{search_term}'")
        found = False
        for name, data in registry["inventory"].items():
            if search_term.lower() in name.lower() or search_term.lower() in str(data).lower():
                found = True
                print(f"\n[Found] {name} ({data['path'])})")
                print(f"  Type: {data['type']}")
                if data['type'] == 'python':
                    print(f"  Docstring: {data.get('docstring')}")
                    print(f"  Functions: {', '.join(data.get('functions', []))}")
                elif data['type'] == 'shell':
                    print(f"  Functions: {', '.join(data.get('functions', []))}")
        if not found:
            print("[-] No matching tools found in registry.")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "scan":
        build_registry()
    else:
        term = sys.argv[1] if len(sys.argv) > 1 else None
        query_registry(term)
