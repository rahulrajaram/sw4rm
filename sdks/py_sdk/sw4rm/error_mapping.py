"""Exception to error code mapping with configurable strategies.

This module provides configurable exception-to-error-code mapping using
the Method Resolution Order (MRO) for proper inheritance handling.
"""

from __future__ import annotations

from typing import Mapping, Protocol, Type, Optional
from . import constants as C


class ErrorCodeMapper(Protocol):
    """Protocol for mapping exceptions to protocol error codes."""
    
    def map_exception(self, exc: Exception) -> int:
        """Map a Python exception to a protocol error code constant."""
        ...


class DictErrorCodeMapper:
    """MRO-based exception mapper using a dictionary of mappings.
    
    This mapper walks the exception's Method Resolution Order (MRO) to find
    the most specific matching exception type, ensuring proper inheritance
    handling.
    """
    
    def __init__(
        self,
        mapping: Mapping[Type[BaseException], int],
        default: int = C.INTERNAL_ERROR
    ) -> None:
        """Initialize the mapper with exception type mappings.
        
        Args:
            mapping: Dictionary mapping exception types to error codes
            default: Error code to use when no mapping is found
        """
        self.mapping = dict(mapping)
        self.default = default
    
    def map_exception(self, exc: Exception) -> int:
        """Map an exception to an error code using MRO traversal.
        
        Args:
            exc: The exception to map
            
        Returns:
            Protocol error code constant
        """
        # Walk the MRO to find the most specific match
        for cls in type(exc).mro():
            if cls in self.mapping:
                return self.mapping[cls]
        return self.default


# Default mapping following protocol error semantics
DEFAULT_EXCEPTION_MAPPING: Mapping[Type[BaseException], int] = {
    # Validation and input errors
    ValueError: C.VALIDATION_ERROR,
    TypeError: C.VALIDATION_ERROR,
    
    # Permission and access errors
    PermissionError: C.PERMISSION_DENIED,
    OSError: C.PERMISSION_DENIED,
    
    # Timeout errors
    TimeoutError: C.ACK_TIMEOUT,
    
    # Network and connectivity errors
    ConnectionError: C.NO_ROUTE,
    ConnectionRefusedError: C.AGENT_UNAVAILABLE,
    ConnectionAbortedError: C.AGENT_SHUTDOWN,
    
    # Resource errors
    MemoryError: C.OVERSIZE_PAYLOAD,
    
    # Runtime errors (more general, should come after specific ones)
    RuntimeError: C.INTERNAL_ERROR,
}

# Default mapper instance using the standard mapping
DEFAULT_MAPPER = DictErrorCodeMapper(DEFAULT_EXCEPTION_MAPPING)


def map_exception_to_error_code(exc: Exception) -> int:
    """Convenience function using the default mapper.
    
    Args:
        exc: Exception to map
        
    Returns:
        Protocol error code constant
        
    Note:
        This function is provided for backward compatibility.
        For more control, use DictErrorCodeMapper directly.
    """
    return DEFAULT_MAPPER.map_exception(exc)