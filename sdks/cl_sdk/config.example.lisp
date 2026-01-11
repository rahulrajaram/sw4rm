;;;; config.example.lisp
;;;;
;;;; Example configuration file for SW4RM Orchestrator
;;;;
;;;; This file demonstrates all available configuration options.
;;;; Copy to your deployment location and customize as needed.
;;;;
;;;; Usage:
;;;;   sw4rm-orchestrator --config /path/to/config.lisp
;;;;
;;;; Format: List of (key value) pairs
;;;; Keys are strings organized hierarchically with dots

(
 ;; ============================================================================
 ;; Orchestrator Identity
 ;; ============================================================================

 ("orchestrator.id" "orchestrator-root")
 ("orchestrator.name" "SW4RM Orchestrator")
 ("orchestrator.version" "0.6.0")

 ;; ============================================================================
 ;; gRPC Server Configuration
 ;; ============================================================================

 ("grpc.host" "0.0.0.0")
 ("grpc.port" 50050)
 ("grpc.max-connections" 100)
 ("grpc.keepalive-interval" 30)      ; seconds
 ("grpc.connection-timeout" 10)      ; seconds

 ;; ============================================================================
 ;; Routing Configuration
 ;; ============================================================================

 ("routing.strategy" "hierarchical")
 ("routing.max-hops" 10)
 ("routing.broadcast-timeout" 5)     ; seconds
 ("routing.allow-loops" nil)

 ;; Routing strategy defaults
 ("routing.strategy.default" "direct")
 ("routing.strategy.fallback" "round-robin")
 ("routing.strategy.health-check-interval" 5)  ; seconds

 ;; ============================================================================
 ;; Checkpoint Configuration
 ;; ============================================================================

 ("checkpoint.enabled" t)
 ("checkpoint.interval" 300)          ; 5 minutes in seconds
 ("checkpoint.path" "/var/sw4rm/checkpoints")
 ("checkpoint.compression" t)
 ("checkpoint.max-history" 10)        ; Keep last 10 checkpoints

 ;; ============================================================================
 ;; Write-Ahead Log (WAL) Configuration
 ;; ============================================================================

 ("wal.enabled" t)
 ("wal.path" "/var/sw4rm/wal")
 ("wal.max-size" 104857600)           ; 100MB in bytes
 ("wal.sync-interval" 1)              ; seconds

 ;; ============================================================================
 ;; Logging Configuration
 ;; ============================================================================

 ("logging.level" "INFO")             ; DEBUG, INFO, WARN, ERROR
 ("logging.file" "/var/log/sw4rm/orchestrator.log")
 ("logging.console" t)
 ("logging.structured" nil)

 ;; ============================================================================
 ;; Metrics Configuration
 ;; ============================================================================

 ("metrics.enabled" t)
 ("metrics.export-format" "prometheus")
 ("metrics.export-port" 9090)
 ("metrics.collection-interval" 10)   ; seconds

 ;; ============================================================================
 ;; Coordination Primitives Configuration
 ;; ============================================================================

 ("coordination.barrier-timeout" 60)           ; seconds
 ("coordination.lease-default-ttl" 30)         ; seconds
 ("coordination.artifact-registry-size" 1000)
 ("coordination.semaphore-default-limit" 10)
 ("coordination.negotiation-timeout" 30)       ; seconds

 ;; ============================================================================
 ;; Health Check Configuration
 ;; ============================================================================

 ("health.heartbeat-interval" 10)    ; seconds
 ("health.heartbeat-timeout" 30)     ; seconds
 ("health.unhealthy-threshold" 3)    ; failed checks before marking unhealthy
)

;;;; End of configuration
