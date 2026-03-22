"""
utils/sanitise.py
"""

_NULL_TOKENS = frozenset({"null", "none", "n/a", "na", ""})

_SENTINEL = "Not specified"


def safe_str(val, sentinel: str = _SENTINEL) -> str:
    if val is None:
        return sentinel
    s = str(val).strip()
    return s if s and s.lower() not in _NULL_TOKENS else sentinel