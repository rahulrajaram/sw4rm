#!/usr/bin/env python3
"""Secret scanning using TruffleHog for pre-commit checks.

Low-noise defaults:
- Scan only staged files (copied to a temp dir)
- Use TruffleHog detectors with --only-verified (no regex/entropy flood)
- Respect exclude paths file and allowlist if present
- Skip large files and likely-binary/non-source files
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List

# Max bytes to scan per file (1 MiB)
MAX_BYTES = 1 * 1024 * 1024

# Extensions we consider most relevant for secrets; keep tight to reduce noise
ALLOWED_EXTS = {
    
    ".py", ".pyi", ".ipynb",
    ".js", ".jsx", ".ts", ".tsx",
    ".json", ".jsonc", ".toml", ".ini", ".cfg",
    ".yml", ".yaml",
    ".env", ".dotenv",
    ".sh", ".bash", ".zsh",
    ".rb", ".go", ".rs", ".java", ".kt", ".gradle", ".cs", ".php", ".pl", ".swift",
    ".proto",
    ".txt",
}

EXCLUDE_FILE = ".trufflehog_exclude.txt"


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


def is_candidate(path: str) -> bool:
    """Rudimentary filter to avoid scanning markdown, media, and unknown binaries."""
    p = Path(path)
    # Only regular files with allowed extensions
    return p.suffix.lower() in ALLOWED_EXTS


def copy_staged_file_content(file_path: str, temp_dir: Path) -> bool:
    """Copy staged content of a file to temp directory."""
    try:
        # Get staged content
        result = subprocess.run(
            ["git", "show", f":{file_path}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True
        )
        
        # Create directory structure
        dest_file = temp_dir / file_path
        dest_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Write staged content
        data = result.stdout
        # Size cap
        if len(data) > MAX_BYTES:
            return False
        with open(dest_file, 'wb') as f:
            f.write(data)
        
        return True
    except (subprocess.CalledProcessError, OSError):
        return False


def run_trufflehog(scan_dir: Path, allowlist_path: Path | None = None) -> List[Dict]:
    """Run TruffleHog scan and return findings."""
    if not subprocess.run(["which", "trufflehog"], capture_output=True).returncode == 0:
        print("[pre-commit] ⚠️  TruffleHog not found, skipping secret scan")
        return []
    
    cmd = [
        "trufflehog",
        "--json",
        "--only-verified",
        f"file://{scan_dir.absolute()}",
    ]
    
    if allowlist_path and allowlist_path.exists():
        cmd.extend(["--allow", str(allowlist_path)])

    # Optional exclude paths file (patterns), if present in repo root
    exclude_file = Path.cwd() / EXCLUDE_FILE
    if exclude_file.exists():
        cmd.extend(["--exclude-paths", str(exclude_file)])
    
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
            if not is_candidate(file_path):
                continue
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
