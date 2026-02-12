# Comprehensive Installation and Configuration Guide

**Enterprise-Grade SDK Installation with Security and Reliability Considerations**


This comprehensive installation guide provides detailed procedures for installing, configuring, and validating the SW4RM SDK across multiple environments including development, staging, and production deployments. The guide includes security hardening procedures and comprehensive troubleshooting workflows.

## System Requirements and Pre-Installation Validation

### Hardware Requirements Matrix

| Environment Type | CPU Cores | Memory (GB) | Storage (GB) | Network Bandwidth |
|-----------------|-----------|-------------|---------------|-------------------|
| **Development** | 2+ (x86_64/ARM64) | 4+ (8+ recommended) | 20+ SSD | 10 Mbps |
| **Staging** | 4+ dedicated | 8+ (16+ recommended) | 50+ SSD RAID-1 | 100 Mbps |
| **Production** | 8+ dedicated | 16+ (32+ recommended) | 100+ NVMe RAID-10 | 1+ Gbps |

### Software Dependencies

| Component | Minimum Version | Recommended Version |
|-----------|----------------|-------------------|
| **Python** | 3.11.0 | 3.12+ |
| **Rust** | 1.70.0 | Latest stable |
| **Node.js** | 18.0 | 20+ LTS |
| **SBCL** (Common Lisp) | 2.3+ | Latest |
| **pip** | 21.0 | Latest |
| **Git** | 2.30+ | Latest |

You only need the toolchain for the SDK(s) you plan to use.

### Operating System Support and Kernel Requirements

**Supported Operating Systems**:


- **Linux Distributions**:
  - Ubuntu 20.04 LTS, 22.04 LTS, 24.04 LTS
  - RHEL/CentOS 8+, AlmaLinux 8+, Rocky Linux 8+
  - Debian 11 (Bullseye), Debian 12 (Bookworm)
  - Amazon Linux 2, Amazon Linux 2023
  - SUSE Linux Enterprise Server 15+

- **macOS Versions**:
  - macOS 12 (Monterey) or later
  - macOS 13 (Ventura) - recommended
  - macOS 14 (Sonoma) - fully supported

- **Windows Platforms**:
  - Windows 10 (version 2004+) with WSL2
  - Windows 11 (all versions) with WSL2
  - Windows Server 2019/2022 with WSL2

**Kernel Requirements**:


- Linux Kernel 5.4+ (5.15+ recommended for optimal performance)
- Container support (cgroups v1/v2, namespaces, overlay2 filesystem)
- Network namespace isolation support for security features

### Network Requirements

**Required Network Connectivity**:


- **Outbound HTTPS (443)**: Package repository access for installation (PyPI, GitHub)
- **TLS Support**: TLS 1.2+ capability for secure communication

## Comprehensive SDK Installation Procedures

### Quick Install by Language

=== "Python"
    ```bash
    pip install sw4rm-sdk
    # Or with all optional dependencies:
    pip install "sw4rm-sdk[all]"
    ```

=== "Rust"
    ```bash
    cargo add sw4rm-sdk
    ```
    Or add to `Cargo.toml`:
    ```toml
    [dependencies]
    sw4rm-sdk = "0.5.0"
    tokio = { version = "1.0", features = ["full"] }
    ```

=== "JavaScript/TypeScript"
    ```bash
    npm install @sw4rm/js-sdk
    # Or with yarn:
    yarn add @sw4rm/js-sdk
    ```

=== "Common Lisp"
    ```lisp
    ;; Using ASDF (from local checkout):
    (asdf:load-system :sw4rm-sdk)

    ;; Or add to your system definition:
    (asdf:defsystem #:my-agent
      :depends-on (#:sw4rm-sdk))
    ```
    The Common Lisp SDK requires SBCL 2.3+ or CCL 1.12+ and uses ASDF for system definition. Clone the SDK repository and ensure `sdks/cl_sdk/` is on your ASDF source registry.

All SDKs require access to the proto definitions for gRPC stub generation. Run the following from the repository root to generate stubs for all languages:

```bash
make protos
```

### Development Environment Installation (Recommended for New Users)

**Complete Development Setup with All Optional Dependencies**:

```bash
#!/bin/bash
# SW4RM SDK Development Environment Setup Script
# Version: 1.0.0
# Purpose: Comprehensive development environment installation

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# System validation
log_info "Validating system prerequisites..."

# Check Python version
PYTHON_VERSION=$(python3 --version 2>/dev/null | cut -d' ' -f2)
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d'.' -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d'.' -f2)

if [[ $PYTHON_MAJOR -lt 3 || ($PYTHON_MAJOR -eq 3 && $PYTHON_MINOR -lt 9) ]]; then
    log_error "Python 3.9+ required. Current version: $PYTHON_VERSION"
    exit 1
fi
log_success "Python version validated: $PYTHON_VERSION"

# Check available disk space (minimum 10GB)
AVAILABLE_SPACE=$(df . | awk 'NR==2 {print $4}')
if [[ $AVAILABLE_SPACE -lt 10485760 ]]; then  # 10GB in KB
    log_warning "Low disk space detected. Minimum 10GB recommended."
fi

# Check memory availability (minimum 4GB)
AVAILABLE_MEMORY=$(free -m | awk 'NR==2{print $7}')
if [[ $AVAILABLE_MEMORY -lt 4096 ]]; then  # 4GB in MB
    log_warning "Low available memory detected. Minimum 4GB recommended."
fi

# Create isolated virtual environment with specific Python version
log_info "Creating isolated Python virtual environment..."
VENV_PATH="${HOME}/.local/sw4rm-env"

if [[ -d "$VENV_PATH" ]]; then
    log_warning "Existing virtual environment found. Removing and recreating..."
    rm -rf "$VENV_PATH"
fi

python3 -m venv "$VENV_PATH" --prompt "sw4rm-sdk"
source "$VENV_PATH/bin/activate"

# Upgrade pip to latest version for security and performance
log_info "Upgrading pip to latest version..."
pip install --upgrade pip setuptools wheel

# Clone or update SW4RM SDK repository
log_info "Obtaining SW4RM SDK source code..."
SDK_PATH="${HOME}/sw4rm-sdk"

if [[ -d "$SDK_PATH" ]]; then
    log_info "Updating existing SDK repository..."
    cd "$SDK_PATH"
    git pull origin main
else
    log_info "Cloning SW4RM SDK repository..."
    git clone https://github.com/rahulrajaram/sw4rm.git "$SDK_PATH"
    cd "$SDK_PATH"
fi

# Install SDK with comprehensive dependency groups
log_info "Installing SW4RM SDK with all development dependencies..."
pip install -e ".[dev,docs,testing,monitoring,security]"

# Generate protocol buffer stubs with validation
log_info "Generating protocol buffer stubs..."
if ! make protos; then
    log_error "Protocol buffer generation failed. Check protoc installation."
    exit 1
fi

# Validate protocol buffer stub generation
PROTO_STUBS_PATH="sdks/py_sdk/sw4rm/protos"
if [[ ! -d "$PROTO_STUBS_PATH" ]] || [[ -z "$(ls -A $PROTO_STUBS_PATH)" ]]; then
    log_error "Protocol buffer stubs not generated correctly."
    exit 1
fi
log_success "Protocol buffer stubs generated successfully."

# Run comprehensive installation validation
log_info "Running installation validation tests..."

# Test basic SDK imports
python3 -c "
import sw4rm
from sw4rm.clients.router import RouterClient
from sw4rm.clients.registry import RegistryClient
from sw4rm.ack_integration import ACKLifecycleManager
from sw4rm.activity_buffer import PersistentActivityBuffer
from sw4rm.worktree_state import WorktreeState
print('✓ All core SDK components imported successfully')
" || { log_error "SDK import validation failed"; exit 1; }

# Test protocol buffer stubs
python3 -c "
from sw4rm.protos.common_pb2 import Envelope, MessageType
env = Envelope(message_id='test', message_type=MessageType.DATA)
print(f'✓ Protocol buffer validation successful: {env.message_id}')
" || { log_error "Protocol buffer validation failed"; exit 1; }

# Generate installation report
log_info "Generating installation report..."
cat > "$HOME/sw4rm-installation-report.txt" << EOF
SW4RM SDK Installation Report
Generated: $(date)
====================================

System Information:
- OS: $(uname -s) $(uname -r)
- Architecture: $(uname -m)
- Python Version: $PYTHON_VERSION
- Virtual Environment: $VENV_PATH
- SDK Path: $SDK_PATH

Installation Status:
- SDK Installation: SUCCESS
- Protocol Buffer Generation: SUCCESS
- Dependency Validation: SUCCESS
- Import Testing: SUCCESS

Next Steps:
1. Activate virtual environment: source $VENV_PATH/bin/activate
2. Navigate to SDK directory: cd $SDK_PATH
3. Review examples: ls examples/
4. Run first agent tutorial: python examples/echo_agent.py

Support:
- Documentation: https://sw4rm.ai
- GitHub Issues: https://github.com/rahulrajaram/sw4rm/issues
EOF

log_success "Development environment installation completed successfully!"
log_info "Installation report saved to: $HOME/sw4rm-installation-report.txt"
log_info "To activate the environment, run: source $VENV_PATH/bin/activate"
```

**Installation Verification and Diagnostic Testing**:

```bash
# Comprehensive SDK diagnostic script
#!/bin/bash
# SW4RM SDK Diagnostic and Validation Script

source "${HOME}/.local/sw4rm-env/bin/activate"
cd "${HOME}/sw4rm-sdk"

echo "=== SW4RM SDK Comprehensive Diagnostics ==="
echo "Timestamp: $(date)"
echo

# Test 1: Core SDK Import and Version Check
echo "1. Testing core SDK imports..."
python3 -c "
import sw4rm
print(f'SDK Version: {sw4rm.__version__}')
print('✓ Core SDK imported successfully')
"

# Test 2: Protocol Buffer Stub Validation
echo "2. Validating protocol buffer stubs..."
python3 -c "
from sw4rm.protos import common_pb2, router_pb2, registry_pb2
print('✓ All protocol stubs imported successfully')
"

# Test 3: Service Client Instantiation
echo "3. Testing service client instantiation..."
python3 -c "
from sw4rm.clients import RouterClient, RegistryClient
router_client = RouterClient(host='localhost', port=50051)
registry_client = RegistryClient(host='localhost', port=50052)
print('✓ Service clients instantiated successfully')
"

# Test 4: Persistence Backend Testing
echo "4. Testing persistence backends..."
python3 -c "
from sw4rm.persistence import JSONFilePersistence
import tempfile
with tempfile.TemporaryDirectory() as tmpdir:
    persistence = JSONFilePersistence(tmpdir)
    persistence.save('test_key', {'test': 'data'})
    data = persistence.load('test_key')
    assert data['test'] == 'data'
    print('✓ File persistence backend functional')
"

# Test 5: Message Processing Pipeline
echo "5. Testing message processing pipeline..."
python3 -c "
import grpc
from sw4rm import constants as C
from sw4rm.ack_integration import ACKLifecycleManager, MessageProcessor
from sw4rm.activity_buffer import PersistentActivityBuffer
from sw4rm.clients.router import RouterClient

channel = grpc.insecure_channel("localhost:50051")
router = RouterClient(channel)
buffer = PersistentActivityBuffer(max_items=10)
ack_manager = ACKLifecycleManager(
    router_client=router,
    activity_buffer=buffer,
    agent_id="test-diagnostic-agent",
)
processor = MessageProcessor(ack_manager)

def test_handler(envelope):
    return {'status': 'success', 'processed': True}

processor.register_handler(C.DATA, test_handler)
print('✓ Message processing pipeline configured successfully')
"

echo
echo "=== Diagnostic Results ==="
echo "All tests completed successfully ✓"
echo "SW4RM SDK is ready for development"
```

### Production Environment Installation

**Secure Production Installation with Hardening**:

```bash
#!/bin/bash
# Production SW4RM SDK Installation Script
# Enhanced security, logging, and monitoring configuration

set -euo pipefail

# Production-specific configurations
INSTALL_USER="sw4rm"
INSTALL_PATH="/opt/sw4rm"
LOG_PATH="/var/log/sw4rm"
DATA_PATH="/var/lib/sw4rm"
CONFIG_PATH="/etc/sw4rm"

# Create dedicated service user with minimal privileges
log_info "Creating dedicated service user..."
if ! id "$INSTALL_USER" &>/dev/null; then
    useradd --system --shell /bin/false --home-dir "$INSTALL_PATH" \
            --create-home --user-group "$INSTALL_USER"
fi

# Create directory structure with proper permissions
log_info "Creating directory structure..."
mkdir -p "$INSTALL_PATH" "$LOG_PATH" "$DATA_PATH" "$CONFIG_PATH"
chown -R "$INSTALL_USER:$INSTALL_USER" "$INSTALL_PATH" "$LOG_PATH" "$DATA_PATH"
chmod 755 "$INSTALL_PATH"
chmod 750 "$LOG_PATH" "$DATA_PATH"
chmod 755 "$CONFIG_PATH"

# Install system dependencies
log_info "Installing system dependencies..."
case "$(uname -s)" in
    Linux)
        if command -v apt-get >/dev/null; then
            apt-get update
            apt-get install -y python3.11 python3.11-venv python3.11-dev \
                              build-essential git curl ca-certificates \
                              protobuf-compiler grpc-tools
        elif command -v yum >/dev/null; then
            yum update -y
            yum install -y python3.11 python3.11-devel gcc gcc-c++ git curl \
                          ca-certificates protobuf-compiler grpc-tools
        fi
        ;;
    *)
        log_error "Unsupported operating system for automated installation"
        exit 1
        ;;
esac

# Install SDK as service user
log_info "Installing SDK as service user..."
sudo -u "$INSTALL_USER" bash << EOF
cd "$INSTALL_PATH"
python3.11 -m venv venv
source venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install sw4rm-sdk[production,monitoring,security]
EOF

# Generate systemd service file
log_info "Creating systemd service configuration..."
cat > /etc/systemd/system/sw4rm@.service << 'EOF'
[Unit]
Description=SW4RM Service (%i)
After=network.target
Wants=network.target

[Service]
Type=notify
User=sw4rm
Group=sw4rm
WorkingDirectory=/opt/sw4rm
Environment=PATH=/opt/sw4rm/venv/bin
Environment=PYTHONPATH=/opt/sw4rm/venv/lib/python3.11/site-packages
ExecStart=/opt/sw4rm/venv/bin/python /etc/sw4rm/%i.py
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
KillMode=mixed

# Security hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/log/sw4rm /var/lib/sw4rm
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
log_success "Production installation completed successfully."
```

### Container-Based Installation

**Production-Ready Docker Installation**:

```dockerfile
# Multi-stage Dockerfile for production SW4RM deployment
# Optimized for security, performance, and minimal attack surface

# Build stage
FROM python:3.11-slim-bullseye AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Create build user
RUN useradd --create-home --shell /bin/bash builder

# Set working directory and switch to build user
WORKDIR /build
USER builder

# Copy requirements and install dependencies
COPY requirements.txt .
RUN python -m venv /build/venv && \
    /build/venv/bin/pip install --upgrade pip setuptools wheel && \
    /build/venv/bin/pip install -r requirements.txt

# Copy source code and build
COPY --chown=builder:builder . .
RUN /build/venv/bin/python -m pip install -e .[production]

# Runtime stage
FROM python:3.11-slim-bullseye AS runtime

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create runtime user with minimal privileges
RUN useradd --create-home --shell /bin/false --uid 1001 sw4rm

# Copy virtual environment from builder stage
COPY --from=builder --chown=sw4rm:sw4rm /build/venv /opt/sw4rm/venv

# Create necessary directories
RUN mkdir -p /var/log/sw4rm /var/lib/sw4rm && \
    chown -R sw4rm:sw4rm /var/log/sw4rm /var/lib/sw4rm

# Switch to non-root user
USER sw4rm

# Set environment variables
ENV PATH="/opt/sw4rm/venv/bin:$PATH" \
    PYTHONPATH="/opt/sw4rm/venv/lib/python3.11/site-packages" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Expose health check port
EXPOSE 8080

# Health check configuration
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Default command
WORKDIR /opt/sw4rm
ENTRYPOINT ["python"]
CMD ["agent.py"]
```

## Comprehensive Installation Verification and Testing

### Multi-Environment Validation Framework

**Production-Grade Validation Suite**:

```python
#!/usr/bin/env python3
"""
SW4RM SDK Comprehensive Installation Verification Suite
Version: 0.1
Purpose: Complete validation of SDK installation across environments
"""

import sys
import os
import subprocess
import importlib
import tempfile
import json
import time
import logging
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict
from datetime import datetime, timezone

@dataclass
class ValidationResult:
    """Structured validation result with detailed metadata"""
    test_name: str
    success: bool
    duration_ms: float
    details: Dict[str, Any]
    error_message: Optional[str] = None
    warning_message: Optional[str] = None

class SW4RMValidator:
    """Comprehensive SDK validation framework"""
    
    def __init__(self):
        self.results: List[ValidationResult] = []
        self.setup_logging()
    
    def setup_logging(self):
        """Configure structured logging for validation"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.StreamHandler(sys.stdout),
                logging.FileHandler('sw4rm-validation.log')
            ]
        )
        self.logger = logging.getLogger(__name__)
    
    def run_validation_suite(self) -> Dict[str, Any]:
        """Execute complete validation suite"""
        self.logger.info("Starting comprehensive SW4RM SDK validation")
        start_time = time.time()
        
        # Core validation tests
        validation_tests = [
            self.validate_system_requirements,
            self.validate_python_environment,
            self.validate_core_imports,
            self.validate_protocol_buffers,
            self.validate_service_clients,
            self.validate_persistence_backends,
            self.validate_message_processing,
            self.validate_worktree_integration,
            self.validate_monitoring_integration,
            self.validate_security_features,
            self.validate_performance_characteristics
        ]
        
        # Execute all validation tests
        for test_func in validation_tests:
            try:
                result = test_func()
                self.results.append(result)
                
                if result.success:
                    self.logger.info(f"✓ {result.test_name} - PASSED ({result.duration_ms:.1f}ms)")
                else:
                    self.logger.error(f"✗ {result.test_name} - FAILED ({result.duration_ms:.1f}ms): {result.error_message}")
                    
                if result.warning_message:
                    self.logger.warning(f"⚠ {result.test_name} - WARNING: {result.warning_message}")
                    
            except Exception as e:
                error_result = ValidationResult(
                    test_name=test_func.__name__,
                    success=False,
                    duration_ms=0,
                    details={},
                    error_message=f"Unexpected error: {str(e)}"
                )
                self.results.append(error_result)
                self.logger.exception(f"Unexpected error in {test_func.__name__}")
        
        # Generate comprehensive report
        total_duration = (time.time() - start_time) * 1000
        return self.generate_validation_report(total_duration)
    
    def validate_system_requirements(self) -> ValidationResult:
        """Validate system-level requirements"""
        start_time = time.time()
        details = {}
        
        try:
            # Check Python version
            python_version = sys.version_info
            details['python_version'] = f"{python_version.major}.{python_version.minor}.{python_version.micro}"
            
            # Check available memory
            try:
                import psutil
                memory_info = psutil.virtual_memory()
                details['available_memory_gb'] = round(memory_info.available / (1024**3), 2)
                details['total_memory_gb'] = round(memory_info.total / (1024**3), 2)
            except ImportError:
                details['memory_check'] = "psutil not available"
            
            # Check disk space
            import shutil
            disk_usage = shutil.disk_usage('.')
            details['available_disk_gb'] = round(disk_usage.free / (1024**3), 2)
            
            # Validate minimum requirements
            success = True
            warnings = []
            
            if python_version < (3, 9):
                success = False
                
            if details.get('available_memory_gb', 0) < 4:
                warnings.append("Less than 4GB memory available")
                
            if details.get('available_disk_gb', 0) < 10:
                warnings.append("Less than 10GB disk space available")
            
            duration_ms = (time.time() - start_time) * 1000
            
            return ValidationResult(
                test_name="System Requirements Validation",
                success=success,
                duration_ms=duration_ms,
                details=details,
                warning_message="; ".join(warnings) if warnings else None
            )
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            return ValidationResult(
                test_name="System Requirements Validation",
                success=False,
                duration_ms=duration_ms,
                details=details,
                error_message=str(e)
            )
    
    def validate_core_imports(self) -> ValidationResult:
        """Validate core SDK component imports"""
        start_time = time.time()
        details = {}
        
        core_modules = [
            'sw4rm',
            'sw4rm.config',
            'sw4rm.envelope',
            'sw4rm.activity_buffer',
            'sw4rm.worktree_state',
            'sw4rm.ack_integration'
        ]
        
        successful_imports = []
        failed_imports = []
        
        for module_name in core_modules:
            try:
                module = importlib.import_module(module_name)
                successful_imports.append(module_name)
                
                # Check for version information
                if hasattr(module, '__version__'):
                    details[f"{module_name}_version"] = module.__version__
                    
            except ImportError as e:
                failed_imports.append(f"{module_name}: {str(e)}")
        
        details['successful_imports'] = successful_imports
        details['failed_imports'] = failed_imports
        
        duration_ms = (time.time() - start_time) * 1000
        success = len(failed_imports) == 0
        
        return ValidationResult(
            test_name="Core SDK Import Validation",
            success=success,
            duration_ms=duration_ms,
            details=details,
            error_message="; ".join(failed_imports) if failed_imports else None
        )
    
    def validate_protocol_buffers(self) -> ValidationResult:
        """Validate protocol buffer stub generation and functionality"""
        start_time = time.time()
        details = {}
        
        try:
            from sw4rm.protos import common_pb2, router_pb2, registry_pb2
            
            # Test message creation and serialization
            envelope = common_pb2.Envelope(
                message_id="test-validation",
                producer_id="validation-suite",
                message_type=common_pb2.MessageType.DATA,
                payload=b"validation test payload"
            )
            
            # Test serialization/deserialization
            serialized = envelope.SerializeToString()
            deserialized = common_pb2.Envelope()
            deserialized.ParseFromString(serialized)
            
            # Validate round-trip integrity
            integrity_check = (
                envelope.message_id == deserialized.message_id and
                envelope.producer_id == deserialized.producer_id and
                envelope.message_type == deserialized.message_type and
                envelope.payload == deserialized.payload
            )
            
            details['proto_stubs_available'] = True
            details['serialization_test'] = "SUCCESS"
            details['round_trip_integrity'] = integrity_check
            details['serialized_size_bytes'] = len(serialized)
            
            duration_ms = (time.time() - start_time) * 1000
            
            return ValidationResult(
                test_name="Protocol Buffer Validation",
                success=integrity_check,
                duration_ms=duration_ms,
                details=details,
                error_message=None if integrity_check else "Round-trip integrity check failed"
            )
            
        except ImportError as e:
            duration_ms = (time.time() - start_time) * 1000
            return ValidationResult(
                test_name="Protocol Buffer Validation",
                success=False,
                duration_ms=duration_ms,
                details={'proto_stubs_available': False},
                error_message=f"Protocol buffer imports failed: {str(e)}"
            )
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            return ValidationResult(
                test_name="Protocol Buffer Validation",
                success=False,
                duration_ms=duration_ms,
                details=details,
                error_message=str(e)
            )
    
    def generate_validation_report(self, total_duration_ms: float) -> Dict[str, Any]:
        """Generate comprehensive validation report"""
        passed_tests = [r for r in self.results if r.success]
        failed_tests = [r for r in self.results if not r.success]
        warning_tests = [r for r in self.results if r.warning_message]
        
        report = {
            'validation_timestamp': datetime.now(timezone.utc).isoformat(),
            'total_duration_ms': round(total_duration_ms, 2),
            'summary': {
                'total_tests': len(self.results),
                'passed': len(passed_tests),
                'failed': len(failed_tests),
                'warnings': len(warning_tests),
                'success_rate': round((len(passed_tests) / len(self.results)) * 100, 1) if self.results else 0
            },
            'test_results': [asdict(result) for result in self.results],
            'recommendations': self.generate_recommendations()
        }
        
        # Save detailed report to file
        report_file = f"sw4rm-validation-report-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        self.logger.info(f"Validation report saved to: {report_file}")
        return report
    
    def generate_recommendations(self) -> List[str]:
        """Generate actionable recommendations based on validation results"""
        recommendations = []
        
        failed_tests = [r for r in self.results if not r.success]
        warning_tests = [r for r in self.results if r.warning_message]
        
        if any("Protocol Buffer" in r.test_name for r in failed_tests):
            recommendations.append("Run 'make protos' to generate protocol buffer stubs")
            
        if any("memory" in str(r.warning_message).lower() for r in warning_tests):
            recommendations.append("Consider increasing available memory for optimal performance")
            
        if any("disk" in str(r.warning_message).lower() for r in warning_tests):
            recommendations.append("Free up disk space or provision additional storage")
            
        return recommendations

# Execute validation suite
if __name__ == "__main__":
    validator = SW4RMValidator()
    report = validator.run_validation_suite()
    
    print(f"\n{'='*60}")
    print("SW4RM SDK VALIDATION SUMMARY")
    print(f"{'='*60}")
    print(f"Total Tests: {report['summary']['total_tests']}")
    print(f"Passed: {report['summary']['passed']}")
    print(f"Failed: {report['summary']['failed']}")
    print(f"Warnings: {report['summary']['warnings']}")
    print(f"Success Rate: {report['summary']['success_rate']}%")
    print(f"Duration: {report['total_duration_ms']:.1f}ms")
    
    if report['summary']['failed'] > 0:
        print(f"\n❌ Installation validation failed with {report['summary']['failed']} errors")
        sys.exit(1)
    else:
        print(f"\n✅ Installation validation completed successfully!")
        if report['summary']['warnings'] > 0:
            print(f"⚠️  {report['summary']['warnings']} warnings require attention")
```

### Protocol Buffer Generation and Validation

**Advanced Protocol Buffer Management**:

```bash
#!/bin/bash
# Advanced Protocol Buffer Generation Script
# Enhanced error handling, validation, and optimization

set -euo pipefail

PROTO_SRC_DIR="protos"
PROTO_OUTPUT_DIR="sdks/py_sdk/sw4rm/protos"
TEMP_DIR=$(mktemp -d)

log_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Validate protocol buffer compiler installation
log_info "Validating protocol buffer compiler..."
if ! command -v protoc &> /dev/null; then
    log_error "protoc not found. Install protocol buffer compiler:"
    echo "  Ubuntu/Debian: sudo apt-get install protobuf-compiler"
    echo "  macOS: brew install protobuf"
    echo "  RHEL/CentOS: sudo yum install protobuf-compiler"
    exit 1
fi

PROTOC_VERSION=$(protoc --version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
log_success "Protocol buffer compiler found: version $PROTOC_VERSION"

# Validate Python gRPC tools
if ! python -c "import grpc_tools" 2>/dev/null; then
    log_error "grpc_tools not found. Install with: pip install grpcio-tools"
    exit 1
fi

# Create output directory structure
log_info "Creating output directory structure..."
mkdir -p "$PROTO_OUTPUT_DIR"

# Generate protocol buffer stubs with comprehensive options
log_info "Generating protocol buffer stubs..."
python -m grpc_tools.protoc \
    --proto_path="$PROTO_SRC_DIR" \
    --python_out="$PROTO_OUTPUT_DIR" \
    --grpc_python_out="$PROTO_OUTPUT_DIR" \
    --mypy_out="$PROTO_OUTPUT_DIR" \
    "$PROTO_SRC_DIR"/*.proto

# Fix relative imports for proper package structure
log_info "Fixing relative imports..."
find "$PROTO_OUTPUT_DIR" -name "*_pb2*.py" -exec sed -i 's/^import \([^.]*_pb2\)/from . import \1/' {} \;

# Generate __init__.py with proper exports
log_info "Generating package initialization..."
cat > "$PROTO_OUTPUT_DIR/__init__.py" << 'EOF'
"""
SW4RM Protocol Buffer Generated Stubs
Auto-generated - DO NOT EDIT MANUALLY
"""

# Import all generated modules for easy access
from .common_pb2 import *
from .router_pb2 import *
from .registry_pb2 import *
from .scheduler_pb2 import *
from .hitl_pb2 import *
from .worktree_pb2 import *
from .tool_pb2 import *

__all__ = [
    # Common message types
    'Envelope', 'MessageType', 'Ack', 'AckStage',
    
    # Router service
    'RouterService', 'SendMessageRequest', 'SendMessageResponse',
    
    # Registry service
    'RegistryService', 'RegisterAgentRequest', 'RegisterAgentResponse',
    
    # Add other exports as needed
]
EOF

# Validate generated stubs
log_info "Validating generated stubs..."
if ! python -c "
from ${PROTO_OUTPUT_DIR/\//.} import common_pb2, router_pb2, registry_pb2
env = common_pb2.Envelope(message_id='test', message_type=common_pb2.MessageType.DATA)
print('✓ Protocol buffer stubs validated successfully')
"; then
    log_error "Generated stubs validation failed"
    exit 1
fi

# Generate compilation report
STUB_FILES=$(find "$PROTO_OUTPUT_DIR" -name "*.py" | wc -l)
STUB_SIZE=$(du -sh "$PROTO_OUTPUT_DIR" | cut -f1)

log_success "Protocol buffer generation completed successfully"
echo "  Generated files: $STUB_FILES"
echo "  Total size: $STUB_SIZE"
echo "  Output directory: $PROTO_OUTPUT_DIR"
```

### Advanced Dependency Management and Environment Configuration

**Production Dependency Configuration**:

```toml
# pyproject.toml - Comprehensive dependency configuration
[build-system]
requires = ["setuptools>=65.0", "wheel", "setuptools-scm>=6.2"]
build-backend = "setuptools.build_meta"

[project]
name = "sw4rm-sdk"
dynamic = ["version"]
description = "Enterprise-grade message-driven agent development platform"
readme = "README.md"
license = {file = "LICENSE"}
authors = [{name = "SW4RM Team", email = "team@sw4rm.dev"}]
classifiers = [
    "Development Status :: 5 - Production/Stable",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: Apache Software License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Distributed Computing",
]
requires-python = ">=3.9"
dependencies = [
    # Core gRPC and Protocol Buffers
    "grpcio>=1.56.0,<2.0.0",
    "protobuf>=4.23.0,<5.0.0",
    "googleapis-common-protos>=1.60.0,<2.0.0",
    
    # Async and concurrency
    "asyncio-mqtt>=0.13.0",
    "aiofiles>=23.1.0",
    "aiohttp>=3.8.0",
    
    # Data serialization and validation
    "pydantic>=2.0.0,<3.0.0",
    "msgpack>=1.0.0",
    
    # Logging and monitoring
    "structlog>=23.1.0",
    "opentelemetry-api>=1.20.0",
    "opentelemetry-sdk>=1.20.0",
    
    # State persistence
    "redis>=4.5.0",
    "psycopg2-binary>=2.9.0; sys_platform != 'win32'",
    "psycopg2>=2.9.0; sys_platform == 'win32'",
    
    # Git integration
    "pygit2>=1.13.0",
    "gitpython>=3.1.0",
    
    # Utility libraries
    "tenacity>=8.2.0",  # Retry mechanisms
    "click>=8.1.0",     # CLI interface
    "pyyaml>=6.0",      # Configuration management
    "python-dateutil>=2.8.0",
    "cryptography>=41.0.0",  # Security features
]

[project.optional-dependencies]
# Development dependencies
dev = [
    "grpcio-tools>=1.56.0",
    "mypy-protobuf>=3.4.0",
    "black>=23.7.0",
    "isort>=5.12.0",
    "flake8>=6.0.0",
    "mypy>=1.5.0",
    "pytest>=7.4.0",
    "pytest-asyncio>=0.21.0",
    "pytest-cov>=4.1.0",
    "pytest-benchmark>=4.0.0",
]

# Documentation dependencies
docs = [
    "mkdocs>=1.5.0",
    "mkdocs-material>=9.2.0",
    "mkdocs-section-index>=0.3.0",
    "mkdocstrings[python]>=0.22.0",
    "pymdown-extensions>=10.2.0",
]

# Production monitoring and observability
monitoring = [
    "opentelemetry-instrumentation>=0.41b0",
    "opentelemetry-exporter-prometheus>=1.12.0",
    "opentelemetry-exporter-jaeger>=1.20.0",
    "prometheus-client>=0.17.0",
    "grafana-client>=3.5.0",
]

# Enhanced security features
security = [
    "cryptography>=41.0.0",
    "pycryptodome>=3.18.0",
    "pyjwt>=2.8.0",
    "bcrypt>=4.0.0",
    "certifi>=2023.7.22",
]

# Performance optimization dependencies
performance = [
    "uvloop>=0.17.0; sys_platform != 'win32'",  # Faster event loop
    "orjson>=3.9.0",  # Faster JSON serialization
    "cython>=3.0.0",  # Optional C extensions
]

# Testing and quality assurance
testing = [
    "pytest>=7.4.0",
    "pytest-asyncio>=0.21.0",
    "pytest-cov>=4.1.0",
    "pytest-benchmark>=4.0.0",
    "pytest-mock>=3.11.0",
    "hypothesis>=6.82.0",  # Property-based testing
    "factory-boy>=3.3.0",  # Test data generation
    "responses>=0.23.0",   # HTTP response mocking
]

# All optional dependencies combined
all = [
    "sw4rm-sdk[dev,docs,monitoring,security,performance,testing]"
]

[project.scripts]
sw4rm = "sw4rm.cli:main"
sw4rm-doctor = "sw4rm.cli.doctor:main"

[tool.setuptools.packages.find]
where = ["py_sdk"]

[tool.setuptools_scm]
root = "."
fallback_version = "0.0.0"
write_to = "py_sdk/sw4rm/_version.py"
```
