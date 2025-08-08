#!/usr/bin/env python3
"""Simple documentation build script."""

import subprocess
import sys
from pathlib import Path

def main():
    """Build documentation with error handling."""
    
    # Ensure we're in the right directory
    repo_root = Path(__file__).parent
    
    print("🔨 Building SigAgent SDK Documentation")
    print(f"📁 Repository: {repo_root}")
    
    # Check if MkDocs is installed
    try:
        result = subprocess.run(["venv/bin/mkdocs", "--version"], 
                              capture_output=True, text=True, cwd=repo_root)
        print(f"📚 MkDocs version: {result.stdout.strip()}")
    except FileNotFoundError:
        print("❌ MkDocs not found. Install with: pip install -e '[docs]'")
        return 1
    
    # Generate protocol buffer stubs first
    print("🔧 Generating protocol buffer stubs...")
    try:
        result = subprocess.run(["make", "protos"], 
                              capture_output=True, text=True, cwd=repo_root)
        if result.returncode == 0:
            print("✅ Protocol stubs generated")
        else:
            print(f"⚠️ Protocol generation warning: {result.stderr}")
    except Exception as e:
        print(f"⚠️ Protocol generation failed: {e}")
    
    # Try to build docs
    print("📖 Building documentation...")
    try:
        result = subprocess.run(["venv/bin/mkdocs", "build", "--strict"], 
                              cwd=repo_root, text=True)
        if result.returncode == 0:
            print("✅ Documentation built successfully!")
            print("📂 Output directory: site/")
            return 0
        else:
            print("❌ Documentation build failed")
            return result.returncode
    except Exception as e:
        print(f"❌ Build error: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())