#!/usr/bin/env python3
"""Secret scanning using TruffleHog for pre-commit checks."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List


def get_staged_files() -> List[str]:
    """Get list of staged files from git."""
    try:
        result = subprocess.run(
            ["git", "diff", "--cached", "--name-only"],
            capture_output=True,
            text=True,
            check=True
        )
        return [f.strip() for f in result.stdout.split('\n') if f.strip()]
    except subprocess.CalledProcessError:
        return []


def copy_staged_file_content(file_path: str, temp_dir: Path) -> bool:
    """Copy staged content of a file to temp directory."""
    try:
        # Get staged content
        result = subprocess.run(
            ["git", "show", f":{file_path}"],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Create directory structure
        dest_file = temp_dir / file_path
        dest_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Write staged content
        with open(dest_file, 'w', encoding='utf-8') as f:
            f.write(result.stdout)
        
        return True
    except (subprocess.CalledProcessError, OSError):
        return False


def run_trufflehog(scan_dir: Path, allowlist_path: Path = None) -> List[Dict]:
    """Run TruffleHog scan and return findings."""
    if not subprocess.run(["which", "trufflehog"], capture_output=True).returncode == 0:
        print("[pre-commit] ⚠️  TruffleHog not found, skipping secret scan")
        return []
    
    cmd = [
        "trufflehog",
        "--json",
        "--regex",
        "--entropy=False",
        f"file://{scan_dir.absolute()}"
    ]
    
    if allowlist_path and allowlist_path.exists():
        cmd.extend(["--allow", str(allowlist_path)])
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=scan_dir)
        
        # Parse JSON output
        findings = []
        if result.stdout.strip():
            for line in result.stdout.strip().split('\n'):
                if line.strip():
                    try:
                        findings.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
        
        return findings
    except subprocess.CalledProcessError as e:
        print(f"[pre-commit] ⚠️  TruffleHog scan failed: {e}")
        return []


def check_secrets() -> int:
    """Main secret checking function."""
    print("[pre-commit] Running TruffleHog secret scan...")
    
    # Get staged files
    staged_files = get_staged_files()
    if not staged_files:
        print("[pre-commit] ✅ No staged files to scan with TruffleHog")
        return 0
    
    # Create temporary directory for staged content
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Copy staged files to temp directory
        copied_files = 0
        for file_path in staged_files:
            if os.path.isfile(file_path) and copy_staged_file_content(file_path, temp_path):
                copied_files += 1
        
        if copied_files == 0:
            print("[pre-commit] ✅ No files to scan with TruffleHog")
            return 0
        
        # Look for allowlist
        repo_root = Path(os.getcwd())
        allowlist_path = repo_root / ".trufflehog_allow.json"
        
        # Run TruffleHog
        findings = run_trufflehog(temp_path, allowlist_path)
        
        if findings:
            print("[pre-commit] ❌ TruffleHog found potential secrets in staged files:")
            for finding in findings:
                path = finding.get('path', 'unknown')
                reason = finding.get('reason', 'unknown')
                strings_found = finding.get('stringsFound', [''])
                secret_snippet = strings_found[0] if strings_found else ''
                print(f"  - {path}: {secret_snippet} - {reason}")
            
            print("\n[pre-commit] Please review and either:")
            print("             1. Remove the secrets from your code")
            print("             2. Add them to .trufflehog_allow.json if they're false positives")
            print("             3. Use 'git commit --no-verify' to bypass this check")
            return 1
        else:
            print("[pre-commit] ✅ TruffleHog scan passed - no secrets detected")
            return 0


if __name__ == "__main__":
    sys.exit(check_secrets())