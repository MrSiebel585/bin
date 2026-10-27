#!/usr/bin/env python3
import os
import sys
import json
import urllib.request
import urllib.error

OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
MODEL_NAME = os.getenv("OMNI_AI_MODEL", "qwen2.5")

def gather_environment_context():
    """Collects current omniscient environment state safely."""
    context = {
        "omni_root": os.getenv("OMNI_ROOT", "/opt/offensive"),
        "omni_workspace": os.getenv("OMNI_WORKSPACE", "Not Set"),
        "target": os.getenv("TARGET", "Not Set"),
        "path": os.getenv("PATH", ""),
        "active_user": os.getenv("USER", "unknown")
    }
    
    # Check log files if they exist
    log_path = os.path.join(context["omni_root"], "logs", "omni.log")
    if os.path.exists(log_path):
        try:
            with open(log_path, "r") as f:
                lines = f.readlines()
                context["recent_logs"] = "".join(lines[-10:])
        except Exception:
            context["recent_logs"] = "Unable to read log file."
    else:
        context["recent_logs"] = "No log file found."
        
    return context

def query_ollama(prompt, context):
    """Sends telemetry and prompt to local Ollama instance."""
    url = f"{OLLAMA_HOST}/api/generate"
    payload = {
        "model": MODEL_NAME,
        "prompt": f"System Context:\n{json.dumps(context, indent=2)}\n\nUser Request:\n{prompt}",
        "stream": False
    }
    
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url, 
        data=data, 
        headers={"Content-Type": "application/json"}
    )
    
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            res_body = json.loads(response.read().decode("utf-8"))
            return res_body.get("response", "No response generated.")
    except urllib.error.URLError as e:
        return f"[!] Error connecting to Ollama at {OLLAMA_HOST}: {e.reason}"

def main():
    if len(sys.argv) < 2:
        prompt = "Analyze the current /opt/offensive environment state, verify configuration hygiene, and suggest next steps for the active target."
    else:
        prompt = " ".join(sys.argv[1:])
        
    print(f"[*] Querying local Ollama model ({MODEL_NAME})...")
    context = gather_environment_context()
    analysis = query_ollama(prompt, context)
    
    print("\n==========================================")
    print(" Omniscient AI Environment Analysis")
    print("==========================================")
    print(analysis)
    print("==========================================")

if __name__ == "__main__":
    main()
