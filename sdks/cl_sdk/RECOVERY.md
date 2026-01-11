# SW4RM Common Lisp Orchestrator: Recovery Semantics

**Version:** 0.6.0
**Last Updated:** 2026-01-11
**Status:** Implementation Complete

## Overview

The SW4RM Common Lisp Orchestrator uses a **checkpoint + WAL** strategy for crash recovery. This document specifies the ordering guarantees, recovery semantics, and failure modes.

---

## Architecture

### Two-Tier Persistence

The orchestrator maintains durability through two complementary mechanisms:

1. **Checkpoints** (`src/persistence/checkpoint.lisp`)
   - Periodic full snapshots of orchestrator state
   - Captures: tree structure, routing tables, leaf registrations, barriers, artifacts
   - Written using `cl-store` for complete object serialization
   - Large, slow to write (seconds for full state)
   - Default interval: 5 minutes (configurable)

2. **Write-Ahead Log (WAL)** (`src/persistence/wal.lisp`)
   - Continuous operation log of incremental changes
   - Binary format with CRC32 checksums for integrity
   - Small, fast to write (microseconds per entry)
   - Operations logged: `:route`, `:register`, `:unregister`, `:deliver`, `:checkpoint`, etc.

**Together:** Checkpoints reduce recovery time (no replay from genesis), WAL minimizes data loss (operations since last checkpoint).

---

## Recovery Ordering Guarantees

### Critical Invariant

**CHECKPOINT-BEFORE-WAL**: The checkpoint represents state at sequence `N`, and WAL replay starts from sequence `N+1`.

```
Timeline:
  t0: Checkpoint saved (sequence 1000)
  t1: WAL entry 1001
  t2: WAL entry 1002
  t3: CRASH

Recovery:
  1. Load checkpoint → state at sequence 1000
  2. Replay WAL from 1001 → applies entries 1001, 1002
  3. Orchestrator resumes at sequence 1002
```

### Sequence Number Monotonicity

- WAL sequence numbers are strictly monotonic (1, 2, 3, ...)
- Each operation gets sequence `N+1` where `N` is the previous max
- **On restart:** `load-wal-sequence` scans the WAL file to find the highest sequence number, then sets next sequence to `max+1`
- **No reuse:** Sequence numbers never repeat across restarts

### Operation Order Preservation

WAL entries are replayed in **ascending sequence order**:

```lisp
(wal-replay wal handler-fn :from-sequence checkpoint-seq)
```

This is implemented by:
1. Reading all entries from disk
2. Merging with in-memory buffer
3. Sorting by sequence number: `(sort entries #'< :key #'wal-entry-sequence)`

**Guarantee:** If operation A happened before operation B (seq_A < seq_B), then A is replayed before B.

---

## Checkpoint and WAL Interaction

### When Checkpoint Happens

Checkpoints are triggered by:
1. **Automatic:** Background thread every `checkpoint.interval` seconds (default: 300s)
2. **Manual:** Explicit call to `save-orchestrator-checkpoint`
3. **Shutdown:** Graceful shutdown saves final checkpoint before exit

### What Gets Logged to Checkpoint

The `orchestrator-state` structure captures:
```lisp
(defstruct orchestrator-state
  tree-snapshot        ; Entire swarm tree (nodes + leaves)
  routing-tables       ; Hash table of routing tables per node
  registered-leaves    ; Leaf host/port/capabilities for reconnection
  pending-envelopes    ; Envelopes not yet delivered
  barriers             ; Active barrier synchronization points
  artifacts            ; Artifact registry
  timestamp            ; Universal time of checkpoint
  version)             ; Checkpoint format version
```

### Checkpoint Does NOT Invalidate WAL

**Important:** Creating a checkpoint does NOT truncate the WAL automatically.

The WAL continues to grow until explicitly managed:
- **Truncate after checkpoint:** `(wal-truncate wal checkpoint-sequence)`
- **Compact to remove corruption:** `(wal-compact wal)`

**Rationale:** This separation allows:
1. Checkpoint to complete successfully before WAL cleanup
2. WAL to serve as audit trail even after checkpoint
3. Recovery to use WAL if checkpoint is corrupted

### Recommended Pattern

```lisp
;; 1. Save checkpoint
(let ((checkpoint-seq (wal-last-sequence *wal*)))
  (save-orchestrator-checkpoint path)

  ;; 2. Truncate WAL (remove entries before checkpoint)
  (wal-truncate *wal* checkpoint-seq))
```

This ensures:
- Checkpoint captures state up to sequence `N`
- WAL truncates all entries `< N`
- WAL retains entries `>= N` for future recovery

---

## Recovery Flow

### Startup Sequence

When orchestrator starts with existing persistence:

```
1. Parse CLI args (--restore checkpoint-file)
2. Load checkpoint file
   - Validate magic bytes (#x5357344D = "SW4M")
   - Verify format version
   - Deserialize orchestrator-state
3. Restore tree structure
4. Restore routing tables
5. Reconnect to Python leaves (gRPC)
6. Restore barriers and artifacts
7. Open WAL file
8. Load WAL sequence number (scan for max)
9. Replay pending WAL entries
   - Filter: sequence > checkpoint timestamp
   - Apply each operation via handler
10. Resume normal operation
```

Implementation: `initialize-orchestrator` in `src/main.lisp`

```lisp
(if-let ((restore-file (getf args :restore-checkpoint)))
  (let ((state (restore-from-checkpoint restore-file)))
    (setf *orchestrator* (orchestrator-state-tree state))
    (restore-orchestrator-state state))
  ;; else: create new orchestrator
  )
```

### WAL Replay Filtering

Replay only operations **after** the checkpoint:

```lisp
(wal-replay wal handler-fn
  :from-sequence (1+ (orchestrator-state-checkpoint-sequence state)))
```

**Why `1+`?** The checkpoint already includes the operation at sequence `N`, so replay starts from `N+1`.

### Handler Idempotency

WAL handlers MUST be idempotent because:
- Recovery may replay the same operation multiple times (if shutdown crashes during replay)
- WAL does not track "already applied" state

Example idempotent handler:
```lisp
(wal-replay wal
  (lambda (entry)
    (case (wal-entry-operation entry)
      (:register
       ;; Check if leaf already registered before adding
       (unless (find-child orchestrator (getf (wal-entry-data entry) :leaf-id))
         (register-leaf orchestrator (wal-entry-data entry))))

      (:route
       ;; Route operations are naturally idempotent (deliver once)
       (route-envelope orchestrator (wal-entry-data entry))))))
```

---

## Edge Cases and Failure Modes

### 1. Checkpoint Corruption

**Scenario:** Checkpoint file is corrupted (disk error, incomplete write).

**Detection:**
- Invalid magic bytes during `validate-magic-bytes`
- Checksum mismatch
- cl-store deserialization error

**Recovery:**
```lisp
(handler-case
    (load-orchestrator-checkpoint path)
  (error (e)
    (warn "Checkpoint corrupted: ~A, starting from scratch" e)
    (make-instance 'swarm-node :id "root")))
```

**Mitigation:**
- Atomic writes: write to `.tmp`, then rename
- Keep multiple checkpoint generations (rotate-checkpoints keeps last 3)
- Verify integrity before deleting old checkpoints

### 2. WAL Corruption

**Scenario:** WAL entry has invalid CRC32 checksum.

**Detection:** `read-wal-entry-from-stream` returns `(values entry NIL)`

**Recovery:**
```lisp
(multiple-value-bind (entry valid-p) (read-wal-entry-from-stream in)
  (unless valid-p
    (log:warn "Corrupted WAL entry at sequence ~D, skipping" seq)
    ;; Continue to next entry (do NOT halt replay)
    ))
```

**Behavior:**
- Corrupted entries are **skipped** with warning
- Replay continues from next valid entry
- This may result in missing operations (data loss bounded by corruption)

**Mitigation:**
- Use `:sync` mode for critical operations
- Run `wal-compact` to remove corrupted entries
- Monitor WAL integrity via `wal-get-stats`

### 3. Partial Checkpoint + Full WAL

**Scenario:** Checkpoint fails mid-write, but WAL is intact.

**State:**
- Checkpoint file is incomplete (magic bytes invalid or truncated)
- WAL has all operations since last good checkpoint

**Recovery:**
- Load previous checkpoint (if available via rotation)
- Replay WAL from that checkpoint's sequence
- More work during replay, but no data loss

### 4. Sequence Number Gaps

**Scenario:** WAL has entries `[1, 2, 5, 6]` (missing 3, 4).

**Cause:**
- Entries 3-4 were never flushed (buffer lost during crash)
- Entries 3-4 were corrupted and skipped

**Recovery:**
- Replay proceeds with available entries
- Missing operations are **lost**
- Application logic must tolerate gaps

**Detection:**
```lisp
(let ((prev-seq 0))
  (dolist (entry entries)
    (when (> (- (wal-entry-sequence entry) prev-seq) 1)
      (warn "WAL gap detected: ~D missing entries between ~D and ~D"
            (- (wal-entry-sequence entry) prev-seq 1)
            prev-seq
            (wal-entry-sequence entry)))
    (setf prev-seq (wal-entry-sequence entry))))
```

### 5. Out-of-Order Replay

**Cannot Happen** due to explicit sorting in `wal-entries`:
```lisp
(sort result #'< :key #'wal-entry-sequence)
```

Even if disk returns entries out of order, or buffer merging is inconsistent, the final replay order is guaranteed monotonic.

### 6. Checkpoint-WAL Timestamp Mismatch

**Scenario:** Checkpoint has timestamp `T1`, but WAL has entries with timestamp `< T1`.

**Cause:**
- Clock skew between checkpoint and WAL writes
- System clock adjusted backward

**Recovery:**
- **Use sequence numbers, NOT timestamps** for replay filtering
- Timestamps are for human debugging only

```lisp
;; CORRECT: Use sequence
(wal-replay wal handler :from-sequence checkpoint-seq)

;; WRONG: Use timestamp (may skip entries)
(wal-replay wal handler :from-timestamp checkpoint-ts)
```

### 7. Concurrent WAL Writes During Checkpoint

**Scenario:** Checkpoint captures state at `t0`, but WAL writes continue during checkpoint save.

**Handling:**
```lisp
(let ((checkpoint-seq (wal-last-sequence *wal*)))  ; Snapshot sequence
  (capture-orchestrator-state orchestrator)         ; Capture state (may take seconds)
  (save-orchestrator-checkpoint path))              ; Write to disk
```

**Problem:** State may not be perfectly consistent with WAL sequence.

**Solution:**
- Hold a read lock during state capture (if concurrency is critical)
- Or: Accept eventual consistency (orchestrator is single-threaded for most operations)

**Current Implementation:** No locking (orchestrator operations are mostly serialized).

---

## Guarantees Provided

### Strong Guarantees

1. **Monotonic Sequence:** Sequence numbers never decrease or repeat
2. **Ordered Replay:** WAL entries are replayed in ascending sequence order
3. **Atomic Checkpoint:** Checkpoint write is atomic (temp file + rename)
4. **Corruption Detection:** CRC32 checksums detect WAL corruption
5. **Idempotent Replay:** Multiple replays of the same entry are safe

### Weak Guarantees

1. **Durability:** Depends on `wal-sync-mode`
   - `:sync` = durable (fsync after each flush)
   - `:async` = NOT durable (OS may lose data)
   - `:batch` = eventually durable

2. **Completeness:** Corrupted WAL entries are skipped (data loss possible)

3. **Consistency:** Checkpoint + WAL may not be perfectly consistent if writes happen during checkpoint

---

## Guarantees NOT Provided

1. **ACID Transactions:** No multi-operation atomicity (use `wal-transaction` macro for logical transactions, but not ACID)
2. **Point-in-Time Recovery:** Cannot restore to arbitrary timestamp (only to checkpoint + WAL)
3. **Automatic Corruption Repair:** Corrupted entries are skipped, not repaired
4. **Byzantine Fault Tolerance:** Assumes non-adversarial failures (no protection against malicious corruption)
5. **Cross-Machine Consistency:** Single-node recovery only (no distributed consensus)

---

## Operational Procedures

### Clean Shutdown

```lisp
1. Stop accepting new operations
2. Flush WAL to disk
   (wal-flush *wal*)
3. Save final checkpoint
   (save-orchestrator-checkpoint path)
4. Truncate WAL (keep only recent entries)
   (wal-truncate *wal* checkpoint-seq)
5. Stop checkpoint thread
   (stop-checkpoint-thread)
6. Close WAL
   (wal-close *wal*)
```

### Disaster Recovery

```lisp
1. Locate last valid checkpoint
   (latest-checkpoint checkpoint-dir)
2. Verify checkpoint integrity
   (verify-checkpoint-integrity path)
3. Restore orchestrator
   (restore-from-checkpoint path)
4. Replay WAL
   (wal-replay *wal* recovery-handler)
5. Resume operations
```

### WAL Maintenance

**When to Compact:**
- WAL file is large (>100MB)
- High rate of corrupted entries
- After major checkpoint rotation

```lisp
(wal-compact *wal*)
;; Returns: (:original-size 104857600
;;           :compacted-size 52428800
;;           :entries-compacted 1000
;;           :entries-dropped 50)
```

**When to Truncate:**
- After successful checkpoint
- When recovering disk space

```lisp
(let ((last-checkpoint-seq (load-last-checkpoint-seq)))
  (wal-truncate *wal* last-checkpoint-seq))
```

---

## Configuration Reference

### Checkpoint Settings

```lisp
*checkpoint-interval*        ; Seconds between auto-checkpoints (default: 300)
*checkpoint-directory*       ; Where to save checkpoints (default: NIL)
*checkpoint-compression*     ; Enable gzip compression (default: T)
```

### WAL Settings

```lisp
(make-wal-log path
  :flush-interval 10         ; Entries before auto-flush (1-100)
  :max-size (* 1024 1024 100) ; Rotate at 100MB
  :sync-mode :batch)          ; :sync | :async | :batch
```

---

## Testing Recovery

### Unit Tests

See `test/wal-tests.lisp` for 69 test cases covering:
- Basic operations (append, flush, close)
- Durability (write-flush-read cycles)
- Integrity (checksum verification, corruption handling)
- Replay (ordered, filtered, idempotent)
- Truncation and compaction

### Integration Test

```lisp
(defun test-crash-recovery ()
  "Simulate crash and verify recovery."
  ;; 1. Create orchestrator
  (let ((orch (make-instance 'swarm-node :id "test")))
    ;; 2. Perform operations
    (register-child orch (make-leaf :id "leaf-1"))
    (route-envelope orch envelope-1)
    ;; 3. Save checkpoint
    (save-orchestrator-checkpoint "/tmp/ckpt.bin")
    ;; 4. More operations
    (route-envelope orch envelope-2)
    (route-envelope orch envelope-3)
    ;; 5. Simulate crash (exit without flush)
    (exit))

  ;; 6. Restart and recover
  (let ((restored (restore-from-checkpoint "/tmp/ckpt.bin")))
    ;; 7. Verify state
    (assert (equal (count-children restored) 1))
    ;; 8. Replay WAL
    (wal-replay *wal* recovery-handler)
    ;; 9. Verify envelopes 2 and 3 were replayed
    ))
```

---

## WAL Lock Sharding (P2-3/P3-10)

### Overview

For high-concurrency workloads, a single WAL buffer lock becomes a bottleneck.
The implementation uses a **16-shard lock pool** to enable concurrent appends
to different shards while maintaining total ordering via global sequence numbers.

### Architecture

```
                    ┌─────────────────────────────────────┐
                    │           Sequence Lock              │
                    │  (allocates globally unique seq#)    │
                    └─────────────────┬───────────────────┘
                                      │
         ┌────────────────────────────┼────────────────────────────┐
         │                            │                            │
         ▼                            ▼                            ▼
┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
│ Shard 0         │        │ Shard 5         │        │ Shard 15        │
│ Lock + Buffer   │        │ Lock + Buffer   │        │ Lock + Buffer   │
│                 │        │                 │        │                 │
│ [entry seq=1]   │        │ [entry seq=3]   │        │ [entry seq=2]   │
│ [entry seq=4]   │        │ [entry seq=6]   │        │ [entry seq=5]   │
└─────────────────┘        └─────────────────┘        └─────────────────┘
         │                            │                            │
         └────────────────────────────┼────────────────────────────┘
                                      │
                                      ▼ (Flush: acquire all locks, merge, sort)
                            ┌─────────────────┐
                            │   WAL File      │
                            │ seq: 1,2,3,4,5,6│
                            └─────────────────┘
```

### Key Components

1. **Shard Locks** (`*wal-shard-locks*`)
   - Array of 16 locks, one per shard
   - Each lock protects its corresponding buffer
   - Acquired in order 0-15 when all locks needed (deadlock prevention)

2. **Shard Buffers** (`*wal-shard-buffers*`)
   - Array of 16 adjustable vectors
   - Entries are appended to the buffer for their shard

3. **Sequence Lock** (`wal-sequence-lock`)
   - Single global lock for sequence number allocation
   - Held briefly to increment and return unique sequence

4. **Shard Index Computation**
   - Uses `sxhash(swarm-id) & 0x0F` (16-bit mask)
   - NIL swarm-id maps to shard 0

### Operation Details

#### `wal-append` with Sharding

```lisp
1. Compute shard-index = hash(swarm-id) & 15
2. Acquire sequence-lock
3.   seq = ++sequence-number
4. Release sequence-lock
5. Create entry with seq
6. Acquire shard-lock[shard-index]
7.   vector-push-extend entry to shard-buffer[shard-index]
8. Release shard-lock[shard-index]
9. If total-shard-entries >= flush-interval: wal-flush
```

#### `wal-flush` with Sharding

```lisp
1. Acquire all 16 shard locks in order (0, 1, 2, ..., 15)
2. Collect entries from all shard buffers
3. Sort collected entries by sequence number (ascending)
4. Write entries to file in sorted order
5. Clear all shard buffers
6. Ensure durability (fsync if sync-mode = :sync)
7. Release all shard locks in reverse order
```

#### `wal-compact` with Sharding

```lisp
1. Acquire all 16 shard locks
2. Flush all pending entries to file
3. Close current file stream
4. Read all entries from file
5. Sort by sequence number
6. Write to temp file
7. Atomic rename temp -> final
8. Reopen file
9. Release all shard locks
```

#### `wal-truncate` with Sharding

```lisp
1. Acquire all 16 shard locks
2. Flush all pending entries
3. Close current stream
4. Read entries >= cutoff sequence
5. Sort by sequence (maintain ordering invariant)
6. Write to temp file
7. Atomic rename
8. Reopen file
9. Release all shard locks
```

### Ordering Invariants

1. **Sequence Monotonicity**: Sequence numbers are strictly increasing globally
2. **Flush Ordering**: Entries are written to disk in sequence order
3. **Replay Ordering**: Entries are replayed in sequence order
4. **Truncation Preservation**: Remaining entries maintain sequence ordering

### Concurrency Guarantees

1. **No Contention Across Shards**: Writers to different swarm-ids proceed in parallel
2. **Global Ordering via Sequence**: Despite concurrent appends, replay is deterministic
3. **Deadlock Prevention**: All-shard operations always acquire locks in order 0-15
4. **Consistent Flush**: Flush sees a consistent snapshot of all shards

### Expected Performance

- **3-16x throughput improvement** under concurrent load (depending on swarm-id distribution)
- **Flush latency**: Slightly higher (must merge and sort), but rare operation
- **Memory**: ~16KB overhead for locks + empty buffers

### Configuration

```lisp
;; Enable sharding (default: T)
(make-wal-log "/var/sw4rm/wal" :sharding-enabled t)

;; Disable sharding (legacy mode)
(make-wal-log "/var/sw4rm/wal" :sharding-enabled nil)

;; Check if sharding is enabled
(wal-sharding-enabled wal)  ; => T or NIL

;; Get shard statistics
(wal-get-stats wal)
;; => (:sharding-enabled T :shard-count 16 :pending-entries 42 ...)
```

### Test Coverage

See `test/wal-tests.lisp` Section 11 for 21 sharding-specific tests:
- Shard index computation
- Concurrent appends to different shards
- Sequence monotonicity across shards
- Flush merges entries correctly
- Compaction coordinates across shards
- Truncation maintains ordering
- Replay in correct sequence

---

## Version History

- **0.6.1** (2026-01-10): WAL lock sharding implementation (P3-10)
- **0.6.0** (2026-01-11): WAL implementation complete, checkpoint cooperative shutdown
- **0.5.0** (2026-01-08): Checkpoint implementation with placeholders
- **0.4.0** (2026-01-05): Initial persistence module structure

---

## References

- `src/persistence/checkpoint.lisp`: Checkpoint implementation
- `src/persistence/wal.lisp`: WAL implementation with 16-shard lock pool
- `test/wal-tests.lisp`: WAL test suite (90+ tests including 21 sharding tests)
- `COMMON_LISP_PLAN.md`: Implementation plan (P2-3 design, P3-10 coordination)
- Write-Ahead Logging: https://en.wikipedia.org/wiki/Write-ahead_logging
- CRC32: IEEE 802.3 polynomial for integrity checking
