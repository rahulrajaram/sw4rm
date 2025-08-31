//! Performance benchmarks for the SW4RM Rust SDK
//!
//! These benchmarks measure performance of key operations:
//! - Envelope creation and serialization
//! - Activity buffer operations  
//! - Message processing throughput
//! - Memory usage patterns
//! - Concurrency performance

use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion, Throughput};
use serde_json::json;
use std::time::{Duration, Instant};
use tempfile::NamedTempFile;
use tokio::runtime::Runtime;

// Import what's available - some may not compile without protoc
use sw4rm_sdk::activity_buffer::{ActivityBuffer, PersistentActivityBuffer};
use sw4rm_sdk::constants;
use sw4rm_sdk::envelope::{EnvelopeBuilder, EnvelopeData};
use sw4rm_sdk::persistence::JsonFilePersistence;
use sw4rm_sdk::Result;
use sw4rm_sdk::{AgentConfig, PreemptionManager};

// Mock Agent trait for benchmarks that can't use the full SDK due to proto compilation
use async_trait::async_trait;

#[async_trait]
#[allow(dead_code)]
trait Agent {
    async fn on_startup(&mut self) -> Result<()>;
    async fn on_shutdown(&mut self) -> Result<()>;
    async fn on_message(&mut self, envelope: EnvelopeData) -> Result<()>;
    async fn on_control(&mut self, envelope: EnvelopeData) -> Result<()>;
    fn config(&self) -> &AgentConfig;
    fn preemption_manager(&self) -> &PreemptionManager;
}

/// Benchmark envelope creation and serialization
fn benchmark_envelope_operations(c: &mut Criterion) {
    let mut group = c.benchmark_group("envelope_operations");

    // Test different payload sizes
    let payload_sizes = vec![100, 1_000, 10_000, 100_000];

    for size in payload_sizes {
        let payload_data = vec![0u8; size];
        let json_payload = json!({
            "data": payload_data,
            "metadata": {
                "size": size,
                "timestamp": chrono::Utc::now().to_rfc3339()
            }
        });

        group.throughput(Throughput::Bytes(size as u64));

        // Benchmark envelope creation
        group.bench_with_input(
            BenchmarkId::new("create_envelope", size),
            &json_payload,
            |b, payload| {
                b.iter(|| {
                    let envelope = EnvelopeBuilder::new(
                        black_box("benchmark-agent".to_string()),
                        black_box(constants::message_type::DATA),
                    )
                    .with_json_payload(black_box(payload))
                    .unwrap()
                    .with_repo_id("benchmark-repo".to_string())
                    .with_worktree_id("main".to_string())
                    .build();

                    black_box(envelope)
                })
            },
        );

        // Benchmark serialization
        let envelope =
            EnvelopeBuilder::new("benchmark-agent".to_string(), constants::message_type::DATA)
                .with_json_payload(&json_payload)
                .unwrap()
                .build();

        group.bench_with_input(
            BenchmarkId::new("serialize_envelope", size),
            &envelope,
            |b, env| {
                b.iter(|| {
                    let serialized = serde_json::to_string(black_box(env)).unwrap();
                    black_box(serialized)
                })
            },
        );

        // Benchmark deserialization
        let serialized = serde_json::to_string(&envelope).unwrap();
        group.bench_with_input(
            BenchmarkId::new("deserialize_envelope", size),
            &serialized,
            |b, data| {
                b.iter(|| {
                    let deserialized: EnvelopeData = serde_json::from_str(black_box(data)).unwrap();
                    black_box(deserialized)
                })
            },
        );
    }

    group.finish();
}

/// Benchmark activity buffer operations
fn benchmark_activity_buffer(c: &mut Criterion) {
    let mut group = c.benchmark_group("activity_buffer");

    // Test different buffer sizes and operation patterns
    let buffer_sizes = vec![100, 1_000, 10_000];

    for capacity in buffer_sizes {
        group.throughput(Throughput::Elements(1));

        // Benchmark in-memory buffer operations
        group.bench_with_input(
            BenchmarkId::new("memory_buffer_record", capacity),
            &capacity,
            |b, &cap| {
                b.iter_custom(|iters| {
                    let mut buffer = ActivityBuffer::new(cap);
                    let test_message = json!({
                        "message_id": "bench-msg",
                        "producer_id": "bench-agent",
                        "message_type": constants::message_type::DATA,
                        "payload": "benchmark data"
                    });

                    let start = Instant::now();
                    for i in 0..iters {
                        let mut msg = test_message.clone();
                        msg["message_id"] = json!(format!("bench-msg-{}", i));
                        buffer.record_incoming(black_box(msg)).unwrap();
                    }
                    start.elapsed()
                })
            },
        );

        // Benchmark persistent buffer operations
        group.bench_with_input(
            BenchmarkId::new("persistent_buffer_record", capacity),
            &capacity,
            |b, &cap| {
                b.iter_custom(|iters| {
                    let temp_file = NamedTempFile::new().unwrap();
                    let persistence = Box::new(JsonFilePersistence::new(temp_file.path()));
                    let buffer = PersistentActivityBuffer::new(cap, Some(persistence)).unwrap();

                    let test_message = json!({
                        "message_id": "bench-msg",
                        "producer_id": "bench-agent",
                        "message_type": constants::message_type::DATA,
                        "payload": "benchmark data"
                    });

                    let start = Instant::now();
                    for i in 0..iters {
                        let mut msg = test_message.clone();
                        msg["message_id"] = json!(format!("bench-msg-{}", i));
                        buffer.record_incoming(black_box(msg)).unwrap();
                    }
                    buffer.flush().unwrap();
                    start.elapsed()
                })
            },
        );

        // Benchmark ACK processing
        let mut buffer = ActivityBuffer::new(capacity);
        let test_messages: Vec<_> = (0..100)
            .map(|i| {
                json!({
                    "message_id": format!("msg-{}", i),
                    "producer_id": "bench-agent",
                    "message_type": constants::message_type::DATA,
                    "payload": format!("data-{}", i)
                })
            })
            .collect();

        // Pre-populate buffer
        for msg in &test_messages {
            buffer.record_incoming(msg.clone()).unwrap();
        }

        group.bench_with_input(
            BenchmarkId::new("ack_processing", capacity),
            &test_messages,
            |b, messages| {
                b.iter(|| {
                    for (i, msg) in messages.iter().enumerate() {
                        let msg_id = msg["message_id"].as_str().unwrap();
                        let ack = json!({
                            "ack_for_message_id": msg_id,
                            "ack_stage": constants::ack_stage::RECEIVED,
                            "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
                            "note": format!("ack-{}", i)
                        });

                        buffer.ack(black_box(&ack));
                    }
                })
            },
        );
    }

    group.finish();
}

/// Benchmark message processing throughput
fn benchmark_message_throughput(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("message_throughput");

    // Test agent message processing throughput
    group.throughput(Throughput::Elements(100));

    group.bench_function("agent_message_processing", |b| {
        b.to_async(&rt).iter(|| async {
            struct BenchmarkAgent {
                processed_count: std::sync::Arc<std::sync::atomic::AtomicU32>,
            }

            #[async_trait]
            impl Agent for BenchmarkAgent {
                async fn on_startup(&mut self) -> Result<()> {
                    Ok(())
                }
                async fn on_shutdown(&mut self) -> Result<()> {
                    Ok(())
                }

                async fn on_message(&mut self, _envelope: EnvelopeData) -> Result<()> {
                    self.processed_count
                        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    // Simulate minimal processing
                    tokio::task::yield_now().await;
                    Ok(())
                }

                async fn on_control(&mut self, _envelope: EnvelopeData) -> Result<()> {
                    Ok(())
                }

                fn config(&self) -> &AgentConfig {
                    static CONFIG: std::sync::OnceLock<AgentConfig> = std::sync::OnceLock::new();
                    CONFIG.get_or_init(|| {
                        AgentConfig::new("bench-agent".to_string(), "Benchmark Agent".to_string())
                    })
                }

                fn preemption_manager(&self) -> &PreemptionManager {
                    static PREEMPTION: std::sync::OnceLock<PreemptionManager> =
                        std::sync::OnceLock::new();
                    PREEMPTION.get_or_init(PreemptionManager::new)
                }
            }

            let processed_count = std::sync::Arc::new(std::sync::atomic::AtomicU32::new(0));
            let mut agent = BenchmarkAgent {
                processed_count: processed_count.clone(),
            };

            let messages: Vec<_> = (0..100)
                .map(|i| {
                    EnvelopeBuilder::new(format!("sender-{}", i), constants::message_type::DATA)
                        .with_json_payload(&json!({"data": i}))
                        .unwrap()
                        .build()
                })
                .collect();

            let start = Instant::now();

            for envelope in messages {
                agent.on_message(black_box(envelope)).await.unwrap();
            }

            let duration = start.elapsed();
            let count = processed_count.load(std::sync::atomic::Ordering::Relaxed);

            black_box((duration, count))
        })
    });

    group.finish();
}

/// Benchmark gRPC-related operations (simplified without full client compilation)
fn benchmark_grpc_simulation(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("grpc_simulation");
    group.sample_size(10);

    // Since we can't compile the full gRPC clients without protoc,
    // we'll benchmark the operations that would be involved
    group.bench_function("message_serialization_for_grpc", |b| {
        b.to_async(&rt).iter(|| async {
            let envelope =
                EnvelopeBuilder::new("grpc-test-agent".to_string(), constants::message_type::DATA)
                    .with_json_payload(&json!({
                        "grpc_operation": "send_message",
                        "data": "test payload for gRPC transmission"
                    }))
                    .unwrap()
                    .build();

            // Simulate what happens in gRPC: serialize to bytes
            let serialized = serde_json::to_vec(&envelope).unwrap();

            // Simulate network transmission delay (minimal)
            tokio::task::yield_now().await;

            // Simulate response deserialization
            let _deserialized: EnvelopeData = serde_json::from_slice(&serialized).unwrap();

            black_box(envelope)
        })
    });

    group.bench_function("connection_establishment_simulation", |b| {
        b.to_async(&rt).iter(|| async {
            // Simulate the overhead of connection establishment
            let start = Instant::now();

            // Simulate DNS resolution and TCP connection (minimal delay)
            tokio::time::sleep(Duration::from_micros(100)).await;

            let connection_time = start.elapsed();
            black_box(connection_time)
        })
    });

    group.finish();
}

/// Benchmark memory usage patterns
fn benchmark_memory_usage(c: &mut Criterion) {
    let mut group = c.benchmark_group("memory_usage");

    // Benchmark memory allocation patterns for different operations
    group.bench_function("envelope_memory_allocation", |b| {
        b.iter(|| {
            let payloads: Vec<_> = (0..1000)
                .map(|i| {
                    EnvelopeBuilder::new(format!("agent-{}", i), constants::message_type::DATA)
                        .with_json_payload(&json!({"data": i, "content": vec![i; 100]}))
                        .unwrap()
                        .build()
                })
                .collect();

            black_box(payloads)
        })
    });

    group.bench_function("activity_buffer_memory_growth", |b| {
        b.iter(|| {
            let mut buffer = ActivityBuffer::new(10000);

            for i in 0..5000 {
                let msg = json!({
                    "message_id": format!("msg-{}", i),
                    "producer_id": "memory-test-agent",
                    "message_type": constants::message_type::DATA,
                    "payload": vec![i % 256; 200]
                });

                buffer.record_incoming(black_box(msg)).unwrap();
            }

            black_box(buffer)
        })
    });

    group.finish();
}

/// Benchmark concurrent operations
fn benchmark_concurrency(c: &mut Criterion) {
    let rt = Runtime::new().unwrap();
    let mut group = c.benchmark_group("concurrency");
    group.sample_size(10);

    group.bench_function("concurrent_envelope_creation", |b| {
        b.to_async(&rt).iter(|| async {
            use tokio::task;

            let tasks: Vec<_> = (0..100)
                .map(|i| {
                    task::spawn(async move {
                        EnvelopeBuilder::new(
                            format!("concurrent-agent-{}", i),
                            constants::message_type::DATA,
                        )
                        .with_json_payload(&json!({"worker": i, "data": vec![i; 50]}))
                        .unwrap()
                        .build()
                    })
                })
                .collect();

            let envelopes: Vec<_> = futures::future::join_all(tasks)
                .await
                .into_iter()
                .map(|r| r.unwrap())
                .collect();

            black_box(envelopes)
        })
    });

    group.bench_function("concurrent_buffer_operations", |b| {
        b.to_async(&rt).iter(|| async {
            use std::sync::Arc;
            use tokio::sync::Mutex;
            use tokio::task;

            let buffer = Arc::new(Mutex::new(ActivityBuffer::new(1000)));

            let tasks: Vec<_> = (0..50)
                .map(|i| {
                    let buffer = buffer.clone();
                    task::spawn(async move {
                        let msg = json!({
                            "message_id": format!("concurrent-msg-{}", i),
                            "producer_id": format!("concurrent-agent-{}", i),
                            "message_type": constants::message_type::DATA,
                            "payload": format!("data-{}", i)
                        });

                        let mut buf = buffer.lock().await;
                        buf.record_incoming(msg).unwrap();
                    })
                })
                .collect();

            futures::future::join_all(tasks).await;

            black_box(buffer)
        })
    });

    group.finish();
}

criterion_group!(
    benches,
    benchmark_envelope_operations,
    benchmark_activity_buffer,
    benchmark_message_throughput,
    benchmark_grpc_simulation,
    benchmark_memory_usage,
    benchmark_concurrency
);

criterion_main!(benches);
