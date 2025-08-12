# SW4RM Rust SDK Performance Benchmarks

This document describes the performance benchmarking suite for the SW4RM Rust SDK and provides guidance on interpreting results and optimizing performance.

## Running Benchmarks

### Basic Benchmark Run
```bash
cargo bench --bench performance_benchmarks
```

### Generate HTML Reports
```bash
cargo bench --bench performance_benchmarks
# View results in target/criterion/reports/index.html
```

### Analyze Results
```bash
python scripts/analyze_performance.py
```

## Benchmark Categories

### 1. Envelope Operations
**Purpose**: Measure performance of core message envelope operations
- **Envelope Creation**: Time to build envelopes with different payload sizes
- **Serialization**: JSON serialization performance across payload sizes
- **Deserialization**: JSON deserialization performance
- **Memory Usage**: Memory allocation patterns for envelopes

**Key Metrics**:

- Envelope creation: Target < 0.1ms
- Serialization: Target < 1ms for small payloads, < 5ms for large payloads
- Memory efficiency: Minimal allocations per envelope

### 2. Activity Buffer Operations
**Purpose**: Measure activity buffer performance characteristics
- **In-Memory Buffer**: Raw performance without persistence
- **Persistent Buffer**: Performance with JSON file persistence
- **ACK Processing**: Acknowledgment handling throughput
- **Memory Growth**: Buffer memory usage patterns

**Key Metrics**:

- Buffer operations: Target < 10μs for in-memory, < 1ms for persistent
- Persistent overhead: Target < 3x slower than in-memory
- ACK processing: Target > 1K ACKs/second

### 3. Message Throughput
**Purpose**: Measure end-to-end message processing performance
- **Agent Message Processing**: Simulated agent message handling
- **Concurrent Processing**: Multi-threaded message handling
- **Pipeline Performance**: Complete message flow simulation

**Key Metrics**:

- Message throughput: Target > 10K messages/second
- Processing latency: Target < 100μs per message
- Concurrent scaling: Target > 2x speedup with concurrency

### 4. gRPC Client Performance
**Purpose**: Measure gRPC client setup and operation overhead
- **Client Creation**: Connection establishment overhead
- **Message Sending**: gRPC message transmission performance
- **Stream Handling**: Streaming message performance

**Key Metrics**:

- Client setup: Target < 1ms
- Message send: Target < 5ms including network
- Stream throughput: Target > 5K messages/second

### 5. Memory Usage Patterns
**Purpose**: Analyze memory allocation and usage patterns
- **Allocation Patterns**: Memory allocation efficiency
- **Buffer Growth**: Memory usage scaling with load
- **Garbage Collection**: Impact of memory cleanup

**Key Metrics**:

- Allocation overhead: Target < 1μs per allocation
- Memory growth: Linear scaling with message count
- GC pressure: Minimal impact on throughput

### 6. Concurrency Performance
**Purpose**: Measure performance under concurrent load
- **Concurrent Envelope Creation**: Parallel envelope operations
- **Concurrent Buffer Access**: Thread-safe buffer operations
- **Task Scaling**: Performance scaling with concurrent tasks

**Key Metrics**:

- Concurrency speedup: Target > 5x with 10+ threads
- Lock contention: Minimal blocking operations
- Resource utilization: Efficient CPU/memory usage

## Performance Targets

### Production Readiness Thresholds

| Operation | Good | Acceptable | Needs Optimization |
|-----------|------|------------|--------------------|
| Envelope Creation | < 0.1ms | < 1ms | > 1ms |
| Serialization (1KB) | < 0.5ms | < 2ms | > 2ms |
| Buffer Operation | < 10μs | < 100μs | > 100μs |
| Message Processing | > 10K/sec | > 1K/sec | < 1K/sec |
| Memory per Message | < 1KB | < 10KB | > 10KB |
| Concurrent Speedup | > 5x | > 2x | < 2x |

### Hardware Assumptions
Benchmarks assume modern hardware:
- CPU: 8+ cores, 3GHz+
- RAM: 8GB+ available
- Storage: SSD for persistent operations

## Optimization Strategies

### 1. Envelope Optimization
- **Pool Envelope Objects**: Reuse envelope structures to reduce allocations
- **Optimize Serialization**: Use faster serialization formats (MessagePack, bincode)
- **Lazy Deserialization**: Delay parsing until needed
- **Zero-Copy Operations**: Minimize data copying where possible

### 2. Buffer Optimization  
- **Async Persistence**: Use tokio for non-blocking I/O
- **Batch Operations**: Group multiple buffer operations
- **Memory Mapping**: Use mmap for large persistent buffers
- **Lock-Free Structures**: Reduce contention with atomic operations

### 3. Concurrency Optimization
- **Work Stealing**: Distribute work efficiently across threads
- **Channel Optimization**: Use optimal channel types for message passing
- **Async Runtime Tuning**: Configure tokio for workload characteristics
- **Memory Locality**: Optimize data structures for cache performance

### 4. Memory Optimization
- **Object Pooling**: Reuse expensive objects
- **Custom Allocators**: Use specialized allocators for hot paths
- **Memory Profiling**: Regular heap analysis with tools like heaptrack
- **Lazy Initialization**: Defer expensive operations until needed

## Continuous Performance Monitoring

### CI/CD Integration
```bash
# Add to CI pipeline
cargo bench --bench performance_benchmarks -- --output-format=json > benchmark_results.json
python scripts/analyze_performance.py
```

### Performance Regression Detection
- Compare benchmark results between commits
- Set up automated alerts for performance degradation
- Track performance trends over time

### Production Monitoring
- Instrument production code with metrics
- Monitor resource usage in deployed environments  
- Set up alerts for performance anomalies

## Interpreting Results

### Understanding Criterion Output
- **Mean**: Average execution time across iterations
- **Std Dev**: Variability in measurements
- **Throughput**: Operations per unit time
- **Confidence Intervals**: Statistical reliability of measurements

### Performance Analysis Script
The `scripts/analyze_performance.py` script provides:
- Automated performance threshold checking
- Comparative analysis across benchmark categories
- Optimization recommendations based on results
- Visual performance trend analysis

### Common Performance Issues
1. **High Variance**: Indicates inconsistent performance, check for resource contention
2. **Memory Leaks**: Growing memory usage, check object lifecycle management
3. **CPU Spikes**: Expensive operations, profile hot code paths
4. **I/O Blocking**: Persistent operations blocking, use async I/O

## Profiling Tools

### Rust-Specific Tools
```bash
# CPU profiling with perf
cargo bench --bench performance_benchmarks -- --profile-time=60

# Memory profiling with valgrind
valgrind --tool=massif --massif-out-file=massif.out target/release/deps/performance_benchmarks-*
ms_print massif.out

# Heap profiling with heaptrack  
heaptrack target/release/deps/performance_benchmarks-*
```

### System Monitoring
```bash
# Monitor resource usage during benchmarks
htop
iotop
nethogs # if testing network operations
```

## Contributing Performance Improvements

### Adding New Benchmarks
1. Add benchmark functions to `benches/performance_benchmarks.rs`
2. Update analysis script to handle new benchmark categories
3. Document expected performance characteristics
4. Add performance targets to CI checks

### Performance Testing Guidelines
- Run benchmarks on consistent hardware
- Avoid other processes during benchmarking
- Run multiple iterations for statistical significance
- Document environmental factors affecting performance

### Reporting Performance Issues
When reporting performance issues, include:
- Benchmark results showing the problem
- Hardware/environment details
- Profiling data when available
- Steps to reproduce performance degradation