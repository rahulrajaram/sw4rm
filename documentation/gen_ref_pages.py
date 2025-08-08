"""Generate the code reference pages and navigation."""

from pathlib import Path
import mkdocs_gen_files

nav = mkdocs_gen_files.Nav()

# Path to the Python package
package_path = Path("py_sdk/sigagent")

# Core modules to document (skip potentially problematic ones for now)
core_modules = [
    "activity_buffer.py",
    "ack_integration.py", 
    "acks.py",
    "config.py",
    "constants.py",
    "envelope.py",
    "persistence.py",
    "worktree_policies.py",
    "worktree_state.py"
]

# Generate documentation for core modules
for module_name in core_modules:
    module_path = package_path / module_name
    if module_path.exists():
        # Convert file path to module path
        relative_path = module_path.relative_to("py_sdk").with_suffix("")
        doc_path = relative_path.with_suffix(".md")
        full_doc_path = Path("reference", doc_path)
        
        # Convert path separators to module notation
        parts = tuple(relative_path.parts)
        
        # Add to navigation
        nav[parts] = doc_path.as_posix()
        
        # Generate the markdown content
        with mkdocs_gen_files.open(full_doc_path, "w") as fd:
            ident = ".".join(parts)
            fd.write(f"# {ident}\n\n")
            fd.write(f"::: {ident}")
        
        # Set edit path for the generated file
        mkdocs_gen_files.set_edit_path(full_doc_path, module_path)

# Generate docs for client modules
clients_path = package_path / "clients"
if clients_path.exists():
    for client_file in clients_path.glob("*.py"):
        if client_file.name.startswith("__"):
            continue
            
        # Convert file path to module path
        relative_path = client_file.relative_to("py_sdk").with_suffix("")
        doc_path = relative_path.with_suffix(".md")
        full_doc_path = Path("reference", doc_path)
        
        # Convert path separators to module notation
        parts = tuple(relative_path.parts)
        
        # Add to navigation
        nav[parts] = doc_path.as_posix()
        
        # Generate the markdown content
        with mkdocs_gen_files.open(full_doc_path, "w") as fd:
            ident = ".".join(parts)
            fd.write(f"# {ident}\n\n")
            fd.write(f"::: {ident}")
        
        # Set edit path for the generated file
        mkdocs_gen_files.set_edit_path(full_doc_path, client_file)

# Write the navigation file
with mkdocs_gen_files.open("reference/SUMMARY.md", "w") as nav_file:
    nav_file.writelines(nav.build_literate_nav())