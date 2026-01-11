.PHONY: help build test clean repl install uninstall quicktest examples services services-stop

# Default target
help:
	@echo "SW4RM Common Lisp Orchestrator SDK - Build Targets"
	@echo ""
	@echo "  make build         - Build standalone executable"
	@echo "  make test          - Run test suite (431 tests)"
	@echo "  make quicktest     - Quick load verification"
	@echo "  make examples      - Verify all examples load"
	@echo "  make repl          - Start REPL with system loaded"
	@echo "  make clean         - Remove build artifacts"
	@echo "  make install       - Install to /usr/local/bin"
	@echo "  make services      - Start reference services (local)"
	@echo "  make services-stop - Stop reference services"
	@echo "  make help          - Show this help message"
	@echo ""

# Build standalone executable
build:
	@echo "Building sw4rm-orchestrator executable..."
	sbcl --load build.lisp
	@echo "Build complete: ./sw4rm-orchestrator"

# Run tests
test:
	@echo "Running test suite (431 tests)..."
	sbcl --non-interactive \
	     --load ~/quicklisp/setup.lisp \
	     --eval '(push *default-pathname-defaults* asdf:*central-registry*)' \
	     --eval '(ql:quickload :sw4rm-orchestrator/test :silent t)' \
	     --eval '(asdf:test-system :sw4rm-orchestrator)' \
	     --eval '(sb-ext:exit :code 0)'

# Start REPL with system loaded
repl:
	@echo "Starting REPL with sw4rm-orchestrator loaded..."
	sbcl --load ~/quicklisp/setup.lisp \
	     --eval '(push *default-pathname-defaults* asdf:*central-registry*)' \
	     --eval '(ql:quickload :sw4rm-orchestrator)' \
	     --eval '(in-package :sw4rm-orchestrator)'

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -f sw4rm-orchestrator
	rm -f *.fasl
	rm -rf .cache
	find . -name "*.fasl" -delete
	@echo "Clean complete"

# Install to system
install: build
	@echo "Installing sw4rm-orchestrator to /usr/local/bin..."
	sudo cp sw4rm-orchestrator /usr/local/bin/
	sudo chmod +x /usr/local/bin/sw4rm-orchestrator
	@echo "Installation complete"

# Uninstall from system
uninstall:
	@echo "Uninstalling sw4rm-orchestrator..."
	sudo rm -f /usr/local/bin/sw4rm-orchestrator
	@echo "Uninstall complete"

# Quick development test (no full test suite)
quicktest:
	@echo "Running quick load verification..."
	sbcl --non-interactive \
	     --load ~/quicklisp/setup.lisp \
	     --eval '(push *default-pathname-defaults* asdf:*central-registry*)' \
	     --eval '(ql:quickload :sw4rm-orchestrator :silent t)' \
	     --eval '(format t "~%System loaded successfully~%")' \
	     --eval '(sb-ext:exit :code 0)'

# Verify all examples load correctly
examples:
	@echo "Verifying all examples load..."
	sbcl --non-interactive \
	     --load ~/quicklisp/setup.lisp \
	     --eval '(push *default-pathname-defaults* asdf:*central-registry*)' \
	     --eval '(ql:quickload :sw4rm-orchestrator :silent t)' \
	     --eval '(load "examples/two-swarm.lisp")' \
	     --eval '(load "examples/hierarchical.lisp")' \
	     --eval '(load "examples/restarts-recovery.lisp")' \
	     --eval '(load "examples/envelope-semantics.lisp")' \
	     --eval '(load "examples/negotiation-room.lisp")' \
	     --eval '(load "examples/cross-swarm-handoff.lisp")' \
	     --eval '(load "examples/microservices.lisp")' \
	     --eval '(load "examples/checkpoint-restore.lisp")' \
	     --eval '(load "examples/tool-streaming.lisp")' \
	     --eval '(load "examples/voting-aggregation.lisp")' \
	     --eval '(format t "~%All 10 examples loaded successfully~%")' \
	     --eval '(sb-ext:exit :code 0)'

# Start reference services (local mode)
services:
	@echo "Starting reference services..."
	cd reference-services && ./start_services.sh --local --no-wait

# Stop reference services
services-stop:
	@echo "Stopping reference services..."
	cd reference-services && ./stop_services.sh --local
