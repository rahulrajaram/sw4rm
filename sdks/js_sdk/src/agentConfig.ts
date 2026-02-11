// Copyright 2025 Rahul Rajaram
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * SDK configuration primitives.
 *
 * Provides typed configuration objects and helpers to centralize service
 * endpoints, agent metadata, and basic runtime knobs. Defaults are sourced
 * from environment variables (SW4RM_* prefix) or hardcoded defaults.
 *
 * This module supports configuration loading from multiple sources:
 * - Environment variables (SW4RM_* prefix)
 * - JSON configuration files
 * - Programmatic configuration
 *
 * @module agentConfig
 */

import * as fs from 'fs';
import * as path from 'path';

/**
 * Addresses for SW4RM services.
 *
 * All service endpoints with their default ports. Individual addresses
 * can be overridden via environment variables or programmatic configuration.
 */
export interface Endpoints {
  /** Router service address (default: http://localhost:50051) */
  router: string;
  /** Registry service address (default: http://localhost:50052) */
  registry: string;
  /** Scheduler service address (default: http://localhost:50053) */
  scheduler: string;
  /** Human-in-the-loop service address (default: http://localhost:50054) */
  hitl: string;
  /** Worktree service address (default: http://localhost:50055) */
  worktree: string;
  /** Tool execution service address (default: http://localhost:50056) */
  tool: string;
  /** Connector service address (default: http://localhost:50057) */
  connector: string;
  /** Negotiation service address (default: http://localhost:50058) */
  negotiation: string;
  /** Reasoning service address (default: http://localhost:50059) */
  reasoning: string;
  /** Logging service address (default: http://localhost:50060) */
  logging: string;
}

/**
 * Retry policy for unary gRPC calls.
 *
 * Controls exponential backoff behavior for transient failures.
 */
export interface RetryPolicy {
  /** Maximum number of retry attempts (default: 3) */
  maxAttempts: number;
  /** Initial backoff delay in milliseconds (default: 200) */
  initialBackoffMs: number;
  /** Maximum backoff delay in milliseconds (default: 2000) */
  maxBackoffMs: number;
  /** Backoff multiplier for exponential backoff (default: 2) */
  multiplier: number;
}

/**
 * Agent runtime configuration.
 *
 * Complete configuration object for an SW4RM agent including:
 * - Identity (agent_id, name, description)
 * - Service endpoints
 * - Timeouts and retry policies
 * - Capabilities and metadata
 */
export interface AgentConfig {
  /** Unique agent identifier */
  agentId: string;
  /** Human-readable agent name */
  name: string;
  /** Optional agent description */
  description?: string;
  /** Agent version (default: "0.1.0") */
  version: string;
  /** List of agent capabilities */
  capabilities: string[];
  /** Service endpoints configuration */
  endpoints: Endpoints;
  /** Request timeout in milliseconds (default: 30000) */
  timeoutMs: number;
  /** Stream keepalive interval in milliseconds (default: 60000) */
  streamKeepaliveMs: number;
  /** Retry policy for unary calls */
  retry: RetryPolicy;
  /** Additional metadata key-value pairs */
  metadata: Record<string, string>;
  /** Communication class (0=UNSPECIFIED, 1=PRIVILEGED, 2=STANDARD, 3=BULK) */
  communicationClass: number;
  /** Supported modalities (e.g., ["application/json", "text/plain"]) */
  modalitiesSupported: string[];
  /** Reasoning connectors this agent can use */
  reasoningConnectors: string[];
  /** Optional public key for cryptographic operations */
  publicKey?: Uint8Array;
}

/**
 * Comprehensive SW4RM SDK configuration.
 *
 * Extended configuration object that includes all SDK settings:
 * - Service endpoints
 * - Timeouts and retry policies
 * - Observability flags (metrics, tracing)
 * - Feature flags
 * - Logging configuration
 */
export interface SW4RMConfig {
  /** Router service address */
  routerAddr: string;
  /** Registry service address */
  registryAddr: string;
  /** Default timeout for operations in milliseconds (default: 30000) */
  defaultTimeoutMs: number;
  /** Maximum number of retry attempts (default: 3) */
  maxRetries: number;
  /** Enable metrics collection and export (default: true) */
  enableMetrics: boolean;
  /** Enable distributed tracing (default: true) */
  enableTracing: boolean;
  /** Logging level: DEBUG, INFO, WARNING, ERROR, CRITICAL (default: INFO) */
  logLevel: string;
  /** Feature flag mappings (name -> value) */
  featureFlags: Record<string, any>;
}

// ---------------------------------------------------------------------------
// Default values and factory functions
// ---------------------------------------------------------------------------

/**
 * Get default endpoints with environment variable overrides.
 *
 * Environment variables supported:
 * - SW4RM_ROUTER_ADDR
 * - SW4RM_REGISTRY_ADDR
 * - SW4RM_SCHEDULER_ADDR
 * - SW4RM_HITL_ADDR
 * - SW4RM_WORKTREE_ADDR
 * - SW4RM_TOOL_ADDR
 * - SW4RM_CONNECTOR_ADDR
 * - SW4RM_NEGOTIATION_ADDR
 * - SW4RM_REASONING_ADDR
 * - SW4RM_LOGGING_ADDR
 *
 * @returns Endpoints configuration with env overrides applied
 */
export function defaultEndpoints(): Endpoints {
  return {
    router: process.env.SW4RM_ROUTER_ADDR || 'http://localhost:50051',
    registry: process.env.SW4RM_REGISTRY_ADDR || 'http://localhost:50052',
    scheduler: process.env.SW4RM_SCHEDULER_ADDR || 'http://localhost:50053',
    hitl: process.env.SW4RM_HITL_ADDR || 'http://localhost:50054',
    worktree: process.env.SW4RM_WORKTREE_ADDR || 'http://localhost:50055',
    tool: process.env.SW4RM_TOOL_ADDR || 'http://localhost:50056',
    connector: process.env.SW4RM_CONNECTOR_ADDR || 'http://localhost:50057',
    negotiation: process.env.SW4RM_NEGOTIATION_ADDR || 'http://localhost:50058',
    reasoning: process.env.SW4RM_REASONING_ADDR || 'http://localhost:50059',
    logging: process.env.SW4RM_LOGGING_ADDR || 'http://localhost:50060',
  };
}

/**
 * Get default retry policy.
 *
 * @returns RetryPolicy with standard exponential backoff settings
 */
export function defaultRetryPolicy(): RetryPolicy {
  return {
    maxAttempts: 3,
    initialBackoffMs: 200,
    maxBackoffMs: 2000,
    multiplier: 2,
  };
}

/**
 * Create a default agent configuration.
 *
 * Provides sensible defaults for all fields. Applications should override
 * at least agentId and name for production use.
 *
 * @param agentId - Optional agent ID (default: "agent-1")
 * @param name - Optional agent name (default: "Agent")
 * @returns AgentConfig with defaults populated
 */
export function defaultAgentConfig(
  agentId: string = 'agent-1',
  name: string = 'Agent'
): AgentConfig {
  return {
    agentId,
    name,
    description: undefined,
    version: '0.1.0',
    capabilities: [],
    endpoints: defaultEndpoints(),
    timeoutMs: 30000,
    streamKeepaliveMs: 60000,
    retry: defaultRetryPolicy(),
    metadata: {},
    communicationClass: 2, // STANDARD
    modalitiesSupported: ['application/json'],
    reasoningConnectors: [],
    publicKey: undefined,
  };
}

/**
 * Load agent configuration from environment variables.
 *
 * Environment variables supported:
 * - AGENT_ID: Agent identifier
 * - AGENT_NAME: Agent name
 * - AGENT_DESCRIPTION: Agent description
 * - AGENT_VERSION: Agent version
 * - AGENT_CAPABILITIES: Comma-separated list of capabilities
 * - SW4RM_TIMEOUT_MS: Request timeout in milliseconds
 * - SW4RM_STREAM_KEEPALIVE_MS: Stream keepalive in milliseconds
 * - SW4RM_RETRY_MAX_ATTEMPTS: Maximum retry attempts
 * - SW4RM_COMMUNICATION_CLASS: Communication class (0-3)
 * - All endpoint environment variables (SW4RM_*_ADDR)
 *
 * @returns AgentConfig populated from environment
 */
export function loadConfigFromEnv(): AgentConfig {
  const config = defaultAgentConfig();

  // Identity
  if (process.env.AGENT_ID) {
    config.agentId = process.env.AGENT_ID;
  }
  if (process.env.AGENT_NAME) {
    config.name = process.env.AGENT_NAME;
  }
  if (process.env.AGENT_DESCRIPTION) {
    config.description = process.env.AGENT_DESCRIPTION;
  }
  if (process.env.AGENT_VERSION) {
    config.version = process.env.AGENT_VERSION;
  }

  // Capabilities
  if (process.env.AGENT_CAPABILITIES) {
    config.capabilities = process.env.AGENT_CAPABILITIES.split(',').map(s => s.trim());
  }

  // Timeouts
  if (process.env.SW4RM_TIMEOUT_MS) {
    const timeout = parseInt(process.env.SW4RM_TIMEOUT_MS, 10);
    if (!isNaN(timeout)) {
      config.timeoutMs = timeout;
    }
  }
  if (process.env.SW4RM_STREAM_KEEPALIVE_MS) {
    const keepalive = parseInt(process.env.SW4RM_STREAM_KEEPALIVE_MS, 10);
    if (!isNaN(keepalive)) {
      config.streamKeepaliveMs = keepalive;
    }
  }

  // Retry
  if (process.env.SW4RM_RETRY_MAX_ATTEMPTS) {
    const attempts = parseInt(process.env.SW4RM_RETRY_MAX_ATTEMPTS, 10);
    if (!isNaN(attempts)) {
      config.retry.maxAttempts = attempts;
    }
  }

  // Communication class
  if (process.env.SW4RM_COMMUNICATION_CLASS) {
    const cls = parseInt(process.env.SW4RM_COMMUNICATION_CLASS, 10);
    if (!isNaN(cls)) {
      config.communicationClass = cls;
    }
  }

  // Endpoints are already loaded via defaultEndpoints()
  config.endpoints = defaultEndpoints();

  return config;
}

// ---------------------------------------------------------------------------
// SW4RMConfig - Enhanced configuration system
// ---------------------------------------------------------------------------

/**
 * Create default SW4RMConfig with environment overrides.
 *
 * @returns SW4RMConfig with defaults and env overrides
 */
export function defaultSW4RMConfig(): SW4RMConfig {
  return {
    routerAddr: process.env.SW4RM_ROUTER_ADDR || 'http://localhost:50051',
    registryAddr: process.env.SW4RM_REGISTRY_ADDR || 'http://localhost:50052',
    defaultTimeoutMs: parseInt(process.env.SW4RM_DEFAULT_TIMEOUT_MS || '30000', 10),
    maxRetries: parseInt(process.env.SW4RM_MAX_RETRIES || '3', 10),
    enableMetrics: parseBool(process.env.SW4RM_ENABLE_METRICS, true),
    enableTracing: parseBool(process.env.SW4RM_ENABLE_TRACING, true),
    logLevel: process.env.SW4RM_LOG_LEVEL || 'INFO',
    featureFlags: {},
  };
}

/**
 * Parse boolean value from string.
 *
 * Accepts: "true", "1", "yes", "on" (case-insensitive) as true.
 * All other values are false.
 *
 * @param value - String value to parse
 * @param defaultValue - Default value if undefined
 * @returns Parsed boolean value
 */
function parseBool(value: string | undefined, defaultValue: boolean): boolean {
  if (value === undefined) {
    return defaultValue;
  }
  return ['true', '1', 'yes', 'on'].includes(value.toLowerCase());
}

/**
 * Load SW4RM configuration from file or environment.
 *
 * Configuration loading order (later sources override earlier ones):
 * 1. Default values
 * 2. Configuration file (if path provided)
 * 3. Environment variables (SW4RM_* prefix)
 *
 * Supported file formats:
 * - JSON (.json)
 *
 * @param configPath - Optional path to configuration file
 * @returns SW4RMConfig instance
 * @throws Error if file doesn't exist or is invalid JSON
 *
 * @example
 * // Load from file and environment
 * const config = loadConfig('/etc/sw4rm/config.json');
 *
 * @example
 * // Load from environment only
 * const config = loadConfig();
 *
 * Environment variables:
 * - SW4RM_ROUTER_ADDR: Router service address
 * - SW4RM_REGISTRY_ADDR: Registry service address
 * - SW4RM_DEFAULT_TIMEOUT_MS: Default timeout in milliseconds
 * - SW4RM_MAX_RETRIES: Maximum retry attempts
 * - SW4RM_ENABLE_METRICS: Enable metrics collection (true/false)
 * - SW4RM_ENABLE_TRACING: Enable tracing (true/false)
 * - SW4RM_LOG_LEVEL: Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
 */
export function loadConfig(configPath?: string): SW4RMConfig {
  let config = defaultSW4RMConfig();

  // Load from file if provided
  if (configPath) {
    if (!fs.existsSync(configPath)) {
      throw new Error(`Configuration file not found: ${configPath}`);
    }

    const ext = path.extname(configPath).toLowerCase();
    if (ext !== '.json') {
      throw new Error(
        `Unsupported configuration file format: ${ext}. ` +
        'Supported formats: .json'
      );
    }

    const fileContent = fs.readFileSync(configPath, 'utf8');
    const fileConfig = JSON.parse(fileContent);

    // Merge file config into defaults
    config = { ...config, ...fileConfig };
  }

  // Environment overrides (already applied in defaultSW4RMConfig)
  // This ensures env vars always win over file config
  const envConfig = loadFromEnv();
  config = { ...config, ...envConfig };

  return config;
}

/**
 * Load configuration overrides from environment variables.
 *
 * @returns Partial SW4RMConfig with env values
 */
function loadFromEnv(): Partial<SW4RMConfig> {
  const envConfig: Partial<SW4RMConfig> = {};

  if (process.env.SW4RM_ROUTER_ADDR) {
    envConfig.routerAddr = process.env.SW4RM_ROUTER_ADDR;
  }

  if (process.env.SW4RM_REGISTRY_ADDR) {
    envConfig.registryAddr = process.env.SW4RM_REGISTRY_ADDR;
  }

  if (process.env.SW4RM_DEFAULT_TIMEOUT_MS) {
    const timeout = parseInt(process.env.SW4RM_DEFAULT_TIMEOUT_MS, 10);
    if (!isNaN(timeout)) {
      envConfig.defaultTimeoutMs = timeout;
    }
  }

  if (process.env.SW4RM_MAX_RETRIES) {
    const retries = parseInt(process.env.SW4RM_MAX_RETRIES, 10);
    if (!isNaN(retries)) {
      envConfig.maxRetries = retries;
    }
  }

  if (process.env.SW4RM_ENABLE_METRICS !== undefined) {
    envConfig.enableMetrics = parseBool(process.env.SW4RM_ENABLE_METRICS, true);
  }

  if (process.env.SW4RM_ENABLE_TRACING !== undefined) {
    envConfig.enableTracing = parseBool(process.env.SW4RM_ENABLE_TRACING, true);
  }

  if (process.env.SW4RM_LOG_LEVEL) {
    envConfig.logLevel = process.env.SW4RM_LOG_LEVEL.toUpperCase();
  }

  return envConfig;
}

// ---------------------------------------------------------------------------
// Global singleton config
// ---------------------------------------------------------------------------

/**
 * Global singleton configuration instance.
 */
let _globalConfig: SW4RMConfig | null = null;

/**
 * Get the global SW4RM configuration.
 *
 * Returns the singleton configuration instance. If no configuration has been
 * loaded yet, creates a new one using environment variables.
 *
 * @returns Global SW4RMConfig instance
 *
 * @example
 * const config = getConfig();
 * console.log(`Router: ${config.routerAddr}`);
 * console.log(`Metrics enabled: ${config.enableMetrics}`);
 */
export function getConfig(): SW4RMConfig {
  if (_globalConfig === null) {
    // Load default config from environment
    _globalConfig = loadConfig();
  }
  return _globalConfig;
}

/**
 * Set the global SW4RM configuration.
 *
 * This allows applications to programmatically configure the SDK
 * instead of using files or environment variables.
 *
 * @param config - SW4RMConfig instance to set as global
 *
 * @example
 * const config: SW4RMConfig = {
 *   routerAddr: 'localhost:50051',
 *   registryAddr: 'localhost:50052',
 *   defaultTimeoutMs: 30000,
 *   maxRetries: 3,
 *   enableMetrics: false,
 *   enableTracing: true,
 *   logLevel: 'DEBUG',
 *   featureFlags: {}
 * };
 * setConfig(config);
 */
export function setConfig(config: SW4RMConfig): void {
  _globalConfig = config;
}

/**
 * Reset the global configuration (primarily for testing).
 *
 * Clears the singleton instance, forcing the next getConfig() call
 * to reload from environment/defaults.
 */
export function resetConfig(): void {
  _globalConfig = null;
}
