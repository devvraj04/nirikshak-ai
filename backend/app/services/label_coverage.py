"""Which faces of the pack were scanned, and does the label itself point to information elsewhere?

Purely deterministic and based only on text that was actually read from the pack:
the 'cues' are verbatim OCR lines such as "Refer Blister card for Regulatory/Statutory information".
Nothing is guessed about what the unscanned part contains.
"""

import re
from typing import Any, Dict, List, Optional

_FACES = ("front", "back", "left", "right", "top", "bottom")

# a "pointer" verb followed shortly by a place on the pack
_CUE_RE = re.compile(
    r"\b(?:see|refer|printed|embossed|given|available|mentioned)\b[^\n]{0,50}"
    r"\b(?:side|sides|bottom|top|base|lid|cap|container|carton|sleeve|blister|card|leaflet|insert|panel)\b",
    re.IGNORECASE,
)


def label_coverage(ocr_text: Optional[str], image_urls: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    scanned: List[str] = [face for face in _FACES if (image_urls or {}).get(face)]
    unscanned = [face for face in _FACES if face not in scanned]

    cues: List[str] = []
    seen = set()
    for line in (ocr_text or "").splitlines():
        text = line.strip()
        if 8 <= len(text) <= 160 and _CUE_RE.search(text) and text.lower() not in seen:
            seen.add(text.lower())
            cues.append(text)

    if cues:
        message = (
            "The label points to information printed elsewhere on the pack "
            "(for example a blister card or the side of the container). "
            "Scan those parts too for a complete analysis."
        )
    else:
        message = ""

    return {
        "scanned_faces": scanned,
        "unscanned_faces": unscanned,
        "cues": cues[:5],
        "info_may_be_elsewhere": bool(cues),
        "message": message,
    }
