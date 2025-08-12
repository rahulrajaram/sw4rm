"""Configurable buffer management strategies.

This module provides pluggable strategies for managing buffer overflow
and item eviction in activity buffers.
"""

from __future__ import annotations

from typing import Protocol, Sequence, Hashable, Iterable, Optional
from collections import deque

ItemId = Hashable


class BufferStrategy(Protocol):
    """Protocol for buffer management strategies.
    
    Strategies determine which items to remove when a buffer exceeds capacity.
    """
    
    def victims(self, order: Sequence[ItemId], excess: int) -> Iterable[ItemId]:
        """Return item IDs to remove when buffer exceeds capacity.
        
        Args:
            order: Sequence of item IDs in insertion order
            excess: Number of items that need to be removed
            
        Returns:
            Iterable of item IDs to remove
        """
        ...


class FIFOBufferStrategy:
    """First-In-First-Out buffer strategy.
    
    Removes the oldest items first when buffer capacity is exceeded.
    This is the most common and predictable strategy.
    """
    
    def victims(self, order: Sequence[ItemId], excess: int) -> Iterable[ItemId]:
        """Return the oldest items for removal.
        
        Args:
            order: Sequence of item IDs in insertion order
            excess: Number of items to remove
            
        Returns:
            List of oldest item IDs to remove
        """
        if excess <= 0:
            return ()
        return list(order)[:excess]


class LIFOBufferStrategy:
    """Last-In-First-Out buffer strategy.
    
    Removes the newest items first when buffer capacity is exceeded.
    This preserves historical data at the expense of recent data.
    """
    
    def victims(self, order: Sequence[ItemId], excess: int) -> Iterable[ItemId]:
        """Return the newest items for removal.
        
        Args:
            order: Sequence of item IDs in insertion order
            excess: Number of items to remove
            
        Returns:
            List of newest item IDs to remove
        """
        if excess <= 0:
            return ()
        return list(order)[-excess:]


class RandomBufferStrategy:
    """Random buffer strategy.
    
    Removes random items when buffer capacity is exceeded.
    This provides unpredictable but fair distribution of removals.
    """
    
    def __init__(self, seed: Optional[int] = None):
        """Initialize with optional random seed for reproducibility."""
        import random
        self._random = random.Random(seed)
    
    def victims(self, order: Sequence[ItemId], excess: int) -> Iterable[ItemId]:
        """Return random items for removal.
        
        Args:
            order: Sequence of item IDs in insertion order
            excess: Number of items to remove
            
        Returns:
            List of randomly selected item IDs to remove
        """
        if excess <= 0:
            return ()
        if excess >= len(order):
            return list(order)
        
        return self._random.sample(list(order), excess)


# Default strategy for backward compatibility
DEFAULT_BUFFER_STRATEGY = FIFOBufferStrategy()