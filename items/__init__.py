"""
items package

This file re-exports the ITEMS registry so that other modules
can simply do:

    from items import ITEMS
"""

# If your big dict is named ITEMS in items.py, use this:
from .items import ITEMS

__all__ = ["ITEMS"]
