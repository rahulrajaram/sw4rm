# Copyright 2025 Rahul Rajaram
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Structured logging for SW4RM agents.

This module provides a structured logging framework for SW4RM agents with support
for correlation IDs, agent IDs, JSON formatting, and integration with Python's
standard logging library.

The logging system supports:
- Structured log format with timestamp, level, agent_id, correlation_id, message, extra
- JSON output format for log aggregation systems
- Standard log levels: DEBUG, INFO, WARNING, ERROR, CRITICAL
- Integration with trace context for correlation ID propagation
"""

from __future__ import annotations

import json
import logging
import sys
from contextvars import ContextVar
from datetime import datetime, timezone
from typing import Any, Optional

# Context variable for current correlation_id (populated by tracing module)
_correlation_id: ContextVar[Optional[str]] = ContextVar("correlation_id", default=None)


class StructuredFormatter(logging.Formatter):
    """Formatter that outputs structured log records.

    Supports both human-readable and JSON output formats. Includes
    agent_id, correlation_id, and custom extra fields in each record.

    Attributes:
        agent_id: Agent identifier to include in all log records
        use_json: Whether to output logs as JSON (default: False)
    """

    def __init__(
        self,
        agent_id: str = "",
        use_json: bool = False,
        *args: Any,
        **kwargs: Any
    ) -> None:
        """Initialize the structured formatter.

        Args:
            agent_id: Agent identifier to include in logs
            use_json: If True, output JSON; if False, human-readable format
            *args: Additional arguments passed to logging.Formatter
            **kwargs: Additional keyword arguments passed to logging.Formatter
        """
        super().__init__(*args, **kwargs)
        self.agent_id = agent_id
        self.use_json = use_json

    def format(self, record: logging.LogRecord) -> str:
        """Format a log record as structured output.

        Args:
            record: The log record to format

        Returns:
            Formatted log string (JSON or human-readable)
        """
        # Get correlation_id from context if available
        correlation_id = _correlation_id.get()

        # Build structured data
        log_data = {
            "timestamp": datetime.fromtimestamp(
                record.created, tz=timezone.utc
            ).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        # Add agent_id if set
        if self.agent_id:
            log_data["agent_id"] = self.agent_id

        # Add correlation_id if available
        if correlation_id:
            log_data["correlation_id"] = correlation_id

        # Add any extra fields from the record
        extra = {}
        for key, value in record.__dict__.items():
            if key not in (
                "name", "msg", "args", "created", "filename", "funcName",
                "levelname", "levelno", "lineno", "module", "msecs",
                "message", "pathname", "process", "processName", "relativeCreated",
                "thread", "threadName", "exc_info", "exc_text", "stack_info",
                "getMessage", "agent_id", "correlation_id"
            ):
                extra[key] = value

        if extra:
            log_data["extra"] = extra

        # Add exception info if present
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)

        # Format as JSON or human-readable
        if self.use_json:
            return json.dumps(log_data, default=str)
        else:
            # Human-readable format
            parts = [
                f"[{log_data['timestamp']}]",
                f"{log_data['level']:8s}",
            ]

            if self.agent_id:
                parts.append(f"[{self.agent_id}]")

            if correlation_id:
                parts.append(f"[{correlation_id[:8]}...]")

            parts.append(f"{log_data['logger']}: {log_data['message']}")

            if extra:
                parts.append(f"extra={json.dumps(extra, default=str)}")

            result = " ".join(parts)

            if "exception" in log_data:
                result += "\n" + log_data["exception"]

            return result


class SW4RMLogger:
    """Wrapper around Python's logging.Logger with SW4RM-specific features.

    Provides structured logging with agent_id, correlation_id, and JSON support.
    Exposes standard logging methods (debug, info, warning, error, critical) with
    automatic context enrichment.

    Attributes:
        logger: Underlying Python logger
        agent_id: Agent identifier for this logger
    """

    def __init__(self, logger: logging.Logger, agent_id: str = "") -> None:
        """Initialize the SW4RM logger.

        Args:
            logger: Underlying Python logger to wrap
            agent_id: Agent identifier to include in all logs
        """
        self.logger = logger
        self.agent_id = agent_id

    def debug(self, message: str, **extra: Any) -> None:
        """Log a debug message.

        Args:
            message: The log message
            **extra: Additional fields to include in the log record
        """
        self.logger.debug(message, extra=extra)

    def info(self, message: str, **extra: Any) -> None:
        """Log an info message.

        Args:
            message: The log message
            **extra: Additional fields to include in the log record
        """
        self.logger.info(message, extra=extra)

    def warning(self, message: str, **extra: Any) -> None:
        """Log a warning message.

        Args:
            message: The log message
            **extra: Additional fields to include in the log record
        """
        self.logger.warning(message, extra=extra)

    def error(self, message: str, exc_info: bool = False, **extra: Any) -> None:
        """Log an error message.

        Args:
            message: The log message
            exc_info: If True, include exception information
            **extra: Additional fields to include in the log record
        """
        self.logger.error(message, exc_info=exc_info, extra=extra)

    def critical(self, message: str, exc_info: bool = False, **extra: Any) -> None:
        """Log a critical message.

        Args:
            message: The log message
            exc_info: If True, include exception information
            **extra: Additional fields to include in the log record
        """
        self.logger.critical(message, exc_info=exc_info, extra=extra)

    def exception(self, message: str, **extra: Any) -> None:
        """Log an exception with traceback.

        This should be called from an exception handler. It automatically
        includes the exception information.

        Args:
            message: The log message
            **extra: Additional fields to include in the log record
        """
        self.logger.exception(message, extra=extra)

    def set_level(self, level: int | str) -> None:
        """Set the logging level.

        Args:
            level: Log level (e.g., logging.DEBUG, "DEBUG", "INFO")
        """
        if isinstance(level, str):
            level = getattr(logging, level.upper())
        self.logger.setLevel(level)


# Registry of loggers by name
_loggers: dict[str, SW4RMLogger] = {}
_default_use_json = False
_default_level = logging.INFO


def configure_logging(
    level: int | str = logging.INFO,
    use_json: bool = False,
) -> None:
    """Configure global logging defaults for SW4RM.

    This should be called once at application startup to set the default
    log level and output format for all SW4RM loggers.

    Args:
        level: Default log level (e.g., logging.DEBUG, "DEBUG", "INFO")
        use_json: If True, output JSON format; if False, human-readable format
    """
    global _default_use_json, _default_level

    if isinstance(level, str):
        level = getattr(logging, level.upper())

    _default_use_json = use_json
    _default_level = level

    # Update existing loggers
    for sw4rm_logger in _loggers.values():
        sw4rm_logger.set_level(level)
        # Update formatter
        for handler in sw4rm_logger.logger.handlers:
            if isinstance(handler.formatter, StructuredFormatter):
                handler.formatter.use_json = use_json


def get_logger(name: str, agent_id: str = "") -> SW4RMLogger:
    """Get or create a SW4RM logger.

    Creates a new logger if one doesn't exist for this name, or returns
    the existing logger. Each logger gets a StructuredFormatter handler
    configured with the provided agent_id.

    Args:
        name: Logger name (typically module name like __name__)
        agent_id: Agent identifier to include in all logs from this logger

    Returns:
        A SW4RMLogger instance

    Example:
        logger = get_logger(__name__, agent_id="agent-42")
        logger.info("Agent started", task_id="task-123")
    """
    # Check if we already have this logger
    cache_key = f"{name}:{agent_id}"
    if cache_key in _loggers:
        return _loggers[cache_key]

    # Create new Python logger
    python_logger = logging.getLogger(name)
    python_logger.setLevel(_default_level)
    python_logger.propagate = False

    # Clear existing handlers to avoid duplicates
    python_logger.handlers.clear()

    # Create handler with structured formatter
    handler = logging.StreamHandler(sys.stdout)
    formatter = StructuredFormatter(agent_id=agent_id, use_json=_default_use_json)
    handler.setFormatter(formatter)
    python_logger.addHandler(handler)

    # Wrap in SW4RMLogger
    sw4rm_logger = SW4RMLogger(python_logger, agent_id=agent_id)
    _loggers[cache_key] = sw4rm_logger

    return sw4rm_logger


def set_correlation_id(correlation_id: Optional[str]) -> None:
    """Set the correlation ID for the current context.

    This is typically called by the tracing module when entering a new
    span. The correlation ID will be automatically included in all logs
    from the current async context.

    Args:
        correlation_id: Correlation ID to set, or None to clear
    """
    _correlation_id.set(correlation_id)


def get_correlation_id() -> Optional[str]:
    """Get the current correlation ID from context.

    Returns:
        Current correlation ID, or None if not set
    """
    return _correlation_id.get()
