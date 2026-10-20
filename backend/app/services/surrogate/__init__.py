"""
NIRIKSHAK AI — Surrogate Advertising & Dark Pattern Detection Module.
"""

from .surrogate_engine import surrogate_engine, SurrogateAdEngine
from .surrogate_database import RESTRICTED_PARENT_BRANDS, KNOWN_CAMOUFLAGE_SKUS
from .dark_pattern_detector import DarkPatternDetector

__all__ = [
    "surrogate_engine",
    "SurrogateAdEngine",
    "DarkPatternDetector",
    "RESTRICTED_PARENT_BRANDS",
    "KNOWN_CAMOUFLAGE_SKUS",
]
