"""Read-only native prop PNG checks used by the worldbuilding gate.

These checks flag measurable preparation problems. They cannot determine native
pixel density, artistic quality, blur, correct sorting or visual wall clipping;
the mandatory visual review and actual Godot 4x render remain separate.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image


def _finite_number(value):
    # Integers are finite without converting them to a potentially overflowing float.
    return type(value) is int or (type(value) is float and math.isfinite(value))


def _small_components(alpha: bytes, width: int, height: int, minimum: int):
    """Return counts and tiny 8-connected alpha islands, including their bounds."""
    remaining = bytearray(pixel > 0 for pixel in alpha)
    tiny = []
    count = 0
    for start in range(len(remaining)):
        if not remaining[start]:
            continue
        count += 1
        remaining[start] = 0
        stack = [start]
        size = 0
        min_y, min_x = divmod(start, width)
        max_x, max_y = min_x, min_y
        while stack:
            index = stack.pop()
            y, x = divmod(index, width)
            size += 1
            min_x, max_x = min(min_x, x), max(max_x, x)
            min_y, max_y = min(min_y, y), max(max_y, y)
            for other_y in range(max(0, y - 1), min(height, y + 2)):
                for other_x in range(max(0, x - 1), min(width, x + 2)):
                    other = other_y * width + other_x
                    if remaining[other]:
                        remaining[other] = 0
                        stack.append(other)
        if size < minimum:
            tiny.append({"pixels": size, "bounds": [min_x, min_y, max_x + 1, max_y + 1]})
    return count, tiny


def _import_params(path: Path):
    """Read only Godot's simple [params] assignments, not Variant metadata."""
    params = {}
    duplicates = set()
    in_params = False
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            in_params = line == "[params]"
        elif in_params and line and not line.startswith((";", "#")) and "=" in line:
            key, value = (part.strip() for part in line.split("=", 1))
            if key in params:
                duplicates.add(key)
            params[key] = value
    return params, duplicates


def check_asset(project: Path, spec: dict) -> dict:
    """Check a source PNG relative to the Godot project (the ``res://`` root).

    Required spec: texture, native_size [integer width, height], anchor [x, y].
    min_component_pixels defaults to 3. alpha_reason, edge_reason and
    components_reason are optional, explicit nonempty review reasons; exceptions
    remain in the report and never exempt a different check. No art is modified.
    """
    result = {
        "passed": False,
        "checks": {name: None for name in (
            "spec", "png", "native_size", "anchor", "nonempty", "alpha",
            "components", "edges", "import",
        )},
        "issues": [],
        "exceptions": [],
        "visual_review_required": True,
    }

    def issue(code, detail):
        result["issues"].append({"code": code, "detail": detail})

    def reviewed(check, code, detail, reason_key):
        if reason_key in spec:
            result["checks"][check] = True
            for exception in result["exceptions"]:
                if exception["check"] == check:
                    exception.update(applied=True, detail=detail)
        else:
            result["checks"][check] = False
            issue(code, detail)

    if not isinstance(spec, dict):
        result["checks"]["spec"] = False
        issue("invalid_spec", "Asset spec must be an object.")
        return result

    native_size = spec.get("native_size")
    if (not isinstance(native_size, (list, tuple)) or len(native_size) != 2
            or any(type(value) is not int or value <= 0 for value in native_size)):
        issue("invalid_spec", "native_size must contain two positive integer pixels.")
    anchor = spec.get("anchor")
    if (not isinstance(anchor, (list, tuple)) or len(anchor) != 2
            or not all(_finite_number(value) for value in anchor)):
        issue("invalid_spec", "anchor must contain two finite numeric image coordinates.")
    elif not result["issues"] and not all(0 <= value <= native_size[index] for index, value in enumerate(anchor)):
        issue("invalid_spec", "anchor must lie within or on the native canvas boundary.")
    minimum = spec.get("min_component_pixels", 3)
    if type(minimum) is not int or minimum <= 0:
        issue("invalid_spec", "min_component_pixels must be a positive integer.")
    for key, check in (("alpha_reason", "alpha"), ("edge_reason", "edges"), ("components_reason", "components")):
        if key in spec:
            if not isinstance(spec[key], str) or not spec[key].strip():
                issue("invalid_spec", f"{key} must be a nonempty review reason.")
            else:
                result["exceptions"].append({
                    "check": check, "reason": spec[key].strip(), "applied": False,
                    "detail": "Declared review exception; no corresponding problem detected yet.",
                })
    if result["issues"]:
        result["checks"]["spec"] = False
        return result
    result["checks"]["spec"] = True
    result["checks"]["anchor"] = True

    texture = spec.get("texture")
    try:
        root = Path(project).resolve()
        if (not isinstance(texture, str) or not texture.startswith("res://")
                or "\\" in texture or "\x00" in texture or ":" in texture[6:]):
            raise ValueError("texture must be a res:// PNG path using forward slashes.")
        source = (root / texture[6:]).resolve()
        if not source.is_relative_to(root) or source.suffix.lower() != ".png":
            raise ValueError("texture must resolve to a PNG inside the Godot project.")
        if not root.is_dir():
            raise ValueError("project must be the existing Godot project directory.")
    except (OSError, RuntimeError, TypeError, ValueError) as error:
        result["checks"]["png"] = False
        issue("invalid_texture", str(error))
        return result
    result["texture"] = texture
    if not source.is_file():
        result["checks"]["png"] = False
        issue("missing_texture", f"Source PNG does not exist: {texture}")
        return result

    try:
        with Image.open(source) as image:
            if image.format != "PNG":
                raise ValueError("Source contents are not PNG.")
            image.load()
            width, height = image.size
            alpha_image = image.convert("RGBA").getchannel("A")
            alpha = alpha_image.tobytes()
            bounds = alpha_image.getbbox()
    except (OSError, ValueError, SyntaxError, Image.DecompressionBombError) as error:
        result["checks"]["png"] = False
        issue("invalid_png", f"Cannot decode source PNG: {error}")
        return result
    result["checks"]["png"] = True
    result["dimensions"] = [width, height]
    result["visible_bounds"] = list(bounds) if bounds else None
    result["checks"]["native_size"] = [width, height] == list(native_size)
    if not result["checks"]["native_size"]:
        issue("native_size", f"Actual canvas {width}x{height}; declared native canvas {native_size[0]}x{native_size[1]}.")
    result["checks"]["nonempty"] = bounds is not None
    if bounds is None:
        issue("empty_art", "Source PNG has no visible pixels.")

    partial = sum(0 < value < 255 for value in alpha)
    result["partial_alpha_pixels"] = partial
    result["checks"]["alpha"] = partial == 0
    if partial:
        reviewed("alpha", "partial_alpha", f"{partial} pixels have partial alpha (1-254); inspect for soft or dirty edges.", "alpha_reason")

    count, tiny = _small_components(alpha, width, height, minimum)
    result["component_count"] = count
    result["small_components"] = tiny[:20]
    result["small_component_count"] = len(tiny)
    result["checks"]["components"] = not tiny
    if tiny:
        reviewed("components", "tiny_components", f"{len(tiny)} disconnected 8-connected islands contain fewer than {minimum} visible pixels; first bounds: {tiny[0]['bounds']}.", "components_reason")

    clipped = bounds is not None and (bounds[0] == 0 or bounds[1] == 0 or bounds[2] == width or bounds[3] == height)
    result["checks"]["edges"] = not clipped
    if clipped:
        reviewed("edges", "clipped_edge", "Visible silhouette touches the canvas edge; inspect for clipped prop pixels.", "edge_reason")

    import_path = source.with_suffix(source.suffix + ".import")
    before_import = len(result["issues"])
    try:
        if not import_path.resolve().is_relative_to(root):
            issue("import_settings", "Source .import settings resolve outside the Godot project.")
        elif not import_path.is_file():
            issue("import_missing", f"Source-side import settings are missing: {texture}.import")
        else:
            params, duplicates = _import_params(import_path)
            required = ("compress/mode", "mipmaps/generate")
            relevant = (*required, "process/size_limit")
            if any(key not in params for key in required) or any(key in duplicates for key in relevant):
                issue("import_settings", "Import requires unambiguous compress/mode and mipmaps/generate settings.")
            else:
                if params["compress/mode"] != "0":
                    issue("import_lossy", "compress/mode must be 0 (Lossless).")
                if params["mipmaps/generate"] != "false":
                    issue("import_mipmaps", "mipmaps/generate must be false.")
                if "process/size_limit" in params and params["process/size_limit"] != "0":
                    issue("import_resize", "process/size_limit must be 0 to preserve the native canvas.")
    except (OSError, RuntimeError, UnicodeError) as error:
        issue("import_settings", f"Cannot read source import settings: {error}")
    result["checks"]["import"] = len(result["issues"]) == before_import
    result["passed"] = not result["issues"]
    return result
