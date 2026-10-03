#!/usr/bin/env python3
import sys
import os
import subprocess
import json
import shutil
from typing import Any, Optional, Union, List, Dict

def get_field_by_path(data: Any, path: str) -> Any:
    """Safely extracts a nested value using a dotted path (e.g. login.password)."""
    path = path.lstrip(".")
    if not path:
        return data
    parts = path.split(".")
    current = data
    for part in parts:
        if isinstance(current, dict):
            current = current.get(part)
        elif isinstance(current, list) and part.isdigit():
            idx = int(part)
            current = current[idx] if 0 <= idx < len(current) else None
        else:
            return None
        if current is None:
            return None
    return current

def _ensure_bw_session() -> str:
    """Ensure an active Bitwarden CLI session exists, prompting for unlock if necessary."""
    session = os.environ.get("BW_SESSION")
    if session:
        return session

    try:
        # Leave stderr uncaptured so the password prompt is visible in the terminal
        result = subprocess.run(
            ["bw", "unlock", "--raw"],
            check=True,
            text=True,
            stdout=subprocess.PIPE
        )
        session = result.stdout.strip()
        os.environ["BW_SESSION"] = session
        return session
    except subprocess.CalledProcessError as e:
        raise RuntimeError("Error unlocking Bitwarden") from e

def get_bitwarden_field(item_name: str, field_path: str = "login.password") -> Any:
    """Core function to fetch a field from Bitwarden, usable via direct import or CLI."""
    if not shutil.which("bw"):
        raise RuntimeError("Bitwarden CLI (bw) not found. Run 'mise install' first.")

    _ensure_bw_session()

    try:
        # Fixed: Added missing opening quote for "--search"
        cmd = ["bw", "list", "items", "--search", item_name]
        result = subprocess.run(cmd, env=os.environ, check=True, text=True, capture_output=True)
        items = json.loads(result.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
        raise RuntimeError(f"Error communicating with Bitwarden CLI: {e}") from e

    if not items:
        raise ValueError(f"No entry found matching '{item_name}'.")

    # Smart selection: Prefer an exact name match over partial search returns
    item = items[0]
    if isinstance(items, list):
        exact_match = next((i for i in items if i.get("name") == item_name), None)
        if exact_match:
            item = exact_match

    if field_path == ".":
        return item

    val = get_field_by_path(item, field_path)
    if val is None or val == "":
        raise ValueError(f"Field '{field_path}' not found for entry '{item_name}' or is empty.")

    return val

def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/bitwarden/bitwarden_get.py <item_name> [field]", file=sys.stderr)
        sys.exit(1)

    item_name = sys.argv[1]
    field_path = sys.argv[2] if len(sys.argv) > 2 else "login.password"

    try:
        val = get_bitwarden_field(item_name, field_path)
        if isinstance(val, (dict, list)):
            print(json.dumps(val))
        else:
            print(val)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()