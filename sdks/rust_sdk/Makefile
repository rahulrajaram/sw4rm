.PHONY: build test clean proto check fmt clippy doc examples

# Default target
all: check build test

# Build the project
build:
	cargo build

# Build in release mode
release:
	cargo build --release

# Run tests
test:
	cargo test

# Run tests with output
test-verbose:
	cargo test -- --nocapture

# Clean build artifacts
clean:
	cargo clean
	rm -rf src/proto/

# Generate protobuf code (handled by build.rs)
proto:
	cargo build

# Run all checks
check: fmt clippy test

# Format code
fmt:
	cargo fmt

# Run clippy linter
clippy:
	cargo clippy --all-targets --all-features -- -D warnings

# Generate documentation
doc:
	cargo doc --open

# Build examples
examples:
	cargo build --examples

# Run echo agent example
echo-example:
	RUST_LOG=info cargo run --example echo_agent

# Run activity buffer demo
activity-demo:
	RUST_LOG=info cargo run --example activity_demo

# Quick test that everything compiles and basic tests pass
quick-test: fmt clippy 
	cargo build --all-targets
	cargo test --lib

# Install development dependencies
dev-deps:
	cargo install cargo-watch
	cargo install cargo-tarpaulin
	cargo install cargo-audit

# Watch for changes and rebuild
watch:
	cargo watch -x build

# Watch and run tests
watch-test:
	cargo watch -x test

# Security audit
audit:
	cargo audit

# Coverage report
coverage:
	cargo tarpaulin --out Html

# Benchmark (if benchmarks exist)
bench:
	cargo bench

# Check for outdated dependencies
outdated:
	cargo outdated

# -----------------------
# Publish helpers
# -----------------------
.PHONY: package publish publish-dry-run

# Create a local crate package (tarball) to verify contents
package:
	cargo package

# Dry-run publish to verify everything is ready for crates.io
publish-dry-run:
	cargo publish --dry-run

# Publish to crates.io (requires CARGO_REGISTRY_TOKEN)
publish:
	cargo publish
