#!/usr/bin/env python3
import argparse
import subprocess
import sys
from pathlib import Path

ENV_PATH = Path("/opt/offensive/venv")

def handle_install(file_path):
    target = Path(file_path)
    if not target.exists():
        print(f"[-] Error: File {target} not found.", file=sys.stderr)
        sys.exit(1)
        
    print(f"[*] Processing script: {target.name}")
    
    # Make executable if shell script
    if target.suffix in [".sh", ".zsh"]:
        subprocess.run(["chmod", "+x", str(target)], check=True)
        
    # Execute script (or test import if python) with virtualenv interpreter
    python_exec = ENV_PATH / "bin" / "python" if ENV_PATH.exists() else Path("python3")
    
    if target.suffix == ".py":
        cmd = [str(python_exec), str(target)]
    else:
        cmd = [str(target)]
        
    result = subprocess.run(cmd, capture_output=True, text=True)
    print(result.stdout)
    if result.stderr:
        print("STDERR:", result.stderr, file=sys.stderr)
        
    sys.exit(result.returncode)

def main():
    parser = argparse.ArgumentParser(description="offensivectl.py Master Controller")
    parser.add_argument("--file", help="Path to incoming script to install and execute")
    args = parser.parse_args()
    
    if args.file:
        handle_install(args.file)
    else:
        print("[*] offensivectl active. Use --file <path> to ingest scripts.")

if __name__ == "__main__":
    main()
