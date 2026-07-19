"""Indian phone-number normalization and validation.

The DB stores numbers in E.164 (`+91XXXXXXXXXX`). Clients may send either the
bare 10 digits or the full +91 form; [normalize_indian_phone] collapses both
to the canonical E.164 string, rejecting anything that isn't a valid Indian
mobile number.
"""

import re

_TEN_DIGIT = re.compile(r"^[6-9]\d{9}$")


def normalize_indian_phone(raw: str) -> str:
    """Return the E.164 form (`+91XXXXXXXXXX`) of an Indian mobile number.

    Accepts `9876543210`, `+919876543210`, `919876543210`, and forms with
    spaces / dashes.

    Raises:
        ValueError: if the number is not a valid 10-digit Indian mobile
            (first digit 6–9).
    """
    digits = re.sub(r"[\s\-()]", "", raw)
    if digits.startswith("+91"):
        digits = digits[3:]
    elif digits.startswith("91") and len(digits) == 12:
        digits = digits[2:]

    if not _TEN_DIGIT.match(digits):
        raise ValueError(
            "Enter a valid 10-digit Indian mobile number (starting 6–9)."
        )
    return f"+91{digits}"
