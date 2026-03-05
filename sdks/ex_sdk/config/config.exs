import Config

config :sw4rm_sdk,
  default_timeout_ms: 30_000,
  default_retry_max_attempts: 3,
  default_heartbeat_interval_ms: 30_000,
  default_ack_timeout_ms: 10_000,
  default_activity_buffer_size: 10_000,
  default_activity_buffer_per_agent: 100,
  default_deduplication_window_seconds: 3600

import_config "#{config_env()}.exs"
