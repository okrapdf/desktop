#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import os
import re
import struct
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


LAYOUT_PROMPT = """Please output the layout information from the PDF image, including each layout element's bbox, its category, and the corresponding text content within the bbox.

1. Bbox format: [x1, y1, x2, y2]

2. Layout Categories: The possible categories are ['Caption', 'Footnote', 'Formula', 'List-item', 'Page-footer', 'Page-header', 'Picture', 'Section-header', 'Table', 'Text', 'Title'].

3. Text Extraction & Formatting Rules:
    - Picture: For the 'Picture' category, the text field should be omitted.
    - Formula: Format its text as LaTeX.
    - Table: Format its text as HTML.
    - All Others (Text, Title, etc.): Format their text as Markdown.

4. Constraints:
    - The output text must be the original text from the image, with no translation.
    - All layout elements must be sorted according to human reading order.

5. Final Output: The entire output must be a single JSON object.
"""

TOKEN_ARTIFACTS = {
    "Ġ": " ",
    "Ċ": "\n",
    "ĉ": "\t",
    "▁": " ",
}
SPECIAL_TOKENS = (
    "<s>",
    "</s>",
    "<|endoftext|>",
    "<|eot_id|>",
    "<|end_of_text|>",
    "<｜end▁of▁sentence｜>",
    "<｜end of sentence｜>",
)
CATEGORY_ALIASES = {
    "caption": "caption",
    "footnote": "footnote",
    "formula": "equation",
    "list-item": "list-item",
    "list_item": "list-item",
    "page-footer": "footer",
    "page_footer": "footer",
    "page-header": "header",
    "page_header": "header",
    "picture": "image",
    "figure": "image",
    "section-header": "heading",
    "section_header": "heading",
    "table": "table",
    "text": "text",
    "title": "title",
}
LAYOUT_LIST_KEYS = (
    "cells",
    "layout",
    "layouts",
    "layout_info",
    "elements",
    "blocks",
    "result",
    "data",
)
IMAGE_FACTOR = 28
MIN_PIXELS = 3_136
MAX_PIXELS = 11_289_600
MODEL_REPOSITORY = "mlx-community/dots.mocr-4bit"
MODEL_REVISION = "708b576de556b0cdba615ecd211db3b951ec09ef"
RUNTIME_LOCK_VERSION = "python>=3.10|mlx-vlm==0.6.6|huggingface-hub==1.24.0|v1"
PAGE_PROVENANCE = (
    f"dots-ocr:model={MODEL_REPOSITORY}@{MODEL_REVISION};"
    f"runtime={RUNTIME_LOCK_VERSION}"
)
SIMULATION_PAGE_PROVENANCE = f"dots-ocr:simulation;worker={RUNTIME_LOCK_VERSION}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run Dots OCR 1.5 (dots.mocr) on rendered PDF pages"
    )
    parser.add_argument("--model", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--page-output-directory", required=True)
    parser.add_argument("--page-progress", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--images", nargs="+", required=True)
    parser.add_argument(
        "--simulate",
        action="store_true",
        help="Exercise the PDF-to-worker contract without loading model weights",
    )
    return parser.parse_args()


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def decode_token_artifacts(raw_text: str) -> tuple[str, int]:
    decoded = raw_text
    replacement_count = 0
    for artifact, replacement in TOKEN_ARTIFACTS.items():
        count = decoded.count(artifact)
        if count:
            decoded = decoded.replace(artifact, replacement)
            replacement_count += count
    for token in SPECIAL_TOKENS:
        decoded = decoded.replace(token, "")
    decoded = decoded.replace("\r\n", "\n").replace("\r", "\n")
    return decoded.strip(), replacement_count


def canonical_category(raw_category: str) -> str:
    normalized = re.sub(r"\s+", "-", raw_category.strip().lower()).strip("-")
    if not normalized:
        return "text"
    return CATEGORY_ALIASES.get(normalized, normalized)


def _json_fence_contents(text: str) -> Iterable[str]:
    pattern = re.compile(r"```(?:json)?\s*(.*?)```", re.IGNORECASE | re.DOTALL)
    for match in pattern.finditer(text):
        yield match.group(1).strip()


def _balanced_json_fragments(text: str) -> Iterable[str]:
    for start, opening in enumerate(text):
        if opening not in "[{":
            continue
        stack = [opening]
        in_string = False
        escaped = False
        for index in range(start + 1, len(text)):
            character = text[index]
            if in_string:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == '"':
                    in_string = False
                continue
            if character == '"':
                in_string = True
                continue
            if character in "[{":
                stack.append(character)
                continue
            if character not in "]}":
                continue
            expected = "[" if character == "]" else "{"
            if not stack or stack[-1] != expected:
                break
            stack.pop()
            if not stack:
                yield text[start : index + 1]
                break


def _layout_cells(payload: Any) -> list[Any] | None:
    if isinstance(payload, list):
        return payload
    if not isinstance(payload, dict):
        return None
    if any(key in payload for key in ("bbox", "bounding_box", "boundingBox")):
        return [payload]
    for key in LAYOUT_LIST_KEYS:
        value = payload.get(key)
        if isinstance(value, list):
            return value
        if isinstance(value, dict):
            nested = _layout_cells(value)
            if nested is not None:
                return nested
    return None


def decode_layout_cells(text: str) -> tuple[list[Any] | None, bool]:
    candidates: list[str] = list(_json_fence_contents(text))
    candidates.append(text.strip())
    candidates.extend(_balanced_json_fragments(text))
    seen: set[str] = set()
    for candidate in candidates:
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        try:
            payload = json.loads(candidate)
        except (json.JSONDecodeError, TypeError):
            continue
        cells = _layout_cells(payload)
        if cells is not None:
            return cells, candidate != text.strip()
    return None, False


def _cell_value(cell: dict[str, Any], keys: tuple[str, ...]) -> Any:
    for key in keys:
        if key in cell:
            return cell[key]
    return None


def _text_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, (int, float, bool)):
        return str(value)
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def source_bbox(cell: dict[str, Any]) -> list[float] | None:
    value = _cell_value(
        cell,
        ("bbox", "bounding_box", "boundingBox", "box"),
    )
    if not isinstance(value, (list, tuple)) or len(value) != 4:
        return None
    try:
        values = [float(coordinate) for coordinate in value]
    except (TypeError, ValueError):
        return None
    if not all(math.isfinite(coordinate) for coordinate in values):
        return None
    return values


def round_by_factor(number: float, factor: int) -> int:
    return round(number / factor) * factor


def ceil_by_factor(number: float, factor: int) -> int:
    return math.ceil(number / factor) * factor


def floor_by_factor(number: float, factor: int) -> int:
    return math.floor(number / factor) * factor


def smart_resize(
    height: int,
    width: int,
    factor: int = IMAGE_FACTOR,
    min_pixels: int = MIN_PIXELS,
    max_pixels: int = MAX_PIXELS,
) -> tuple[int, int]:
    """Match the Qwen/Dots processor's model-input dimensions."""
    if height <= 0 or width <= 0:
        raise ValueError("Image dimensions must be positive")
    aspect_ratio = max(height, width) / min(height, width)
    if aspect_ratio > 200:
        raise ValueError(
            f"absolute aspect ratio must be smaller than 200, got {aspect_ratio}"
        )
    resized_height = max(factor, round_by_factor(height, factor))
    resized_width = max(factor, round_by_factor(width, factor))
    if resized_height * resized_width > max_pixels:
        beta = math.sqrt((height * width) / max_pixels)
        resized_height = max(factor, floor_by_factor(height / beta, factor))
        resized_width = max(factor, floor_by_factor(width / beta, factor))
    elif resized_height * resized_width < min_pixels:
        beta = math.sqrt(min_pixels / (height * width))
        resized_height = ceil_by_factor(height * beta, factor)
        resized_width = ceil_by_factor(width * beta, factor)
        if resized_height * resized_width > max_pixels:
            beta = math.sqrt((resized_height * resized_width) / max_pixels)
            resized_height = max(
                factor,
                floor_by_factor(resized_height / beta, factor),
            )
            resized_width = max(
                factor,
                floor_by_factor(resized_width / beta, factor),
            )
    return resized_height, resized_width


def normalized_bbox(
    values: list[float],
    input_width: int,
    input_height: int,
) -> dict[str, float | str]:
    if input_width <= 0 or input_height <= 0:
        raise ValueError("Image dimensions must be positive")
    x1, y1, x2, y2 = values
    left, right = sorted(
        (min(max(x1, 0.0), float(input_width)), min(max(x2, 0.0), float(input_width)))
    )
    top, bottom = sorted(
        (
            min(max(y1, 0.0), float(input_height)),
            min(max(y2, 0.0), float(input_height)),
        )
    )
    return {
        "x": round(left / input_width, 6),
        "y": round(top / input_height, 6),
        "width": round((right - left) / input_width, 6),
        "height": round((bottom - top) / input_height, 6),
        "unit": "normalized",
        "origin": "top-left",
    }


def block_markdown(block: dict[str, Any]) -> str:
    text = block["text"].strip()
    category = block["type"]
    if category == "image":
        return f"> Figure: {text}" if text else ""
    if not text:
        return ""
    if category == "title":
        return text if text.startswith("#") else f"### {text}"
    if category == "heading":
        return text if text.startswith("#") else f"#### {text}"
    if category == "list-item":
        return text if re.match(r"^(?:[-*+] |\d+[.)] )", text) else f"- {text}"
    if category == "equation":
        return text if text.startswith(("$", "\\[", "\\(")) else f"$$\n{text}\n$$"
    if category == "caption":
        return text if text.startswith("_") else f"_{text}_"
    return text


def parse_model_output(
    raw_text: str,
    page_number: int,
    image_file: str,
    image_width: int,
    image_height: int,
    provenance: str = PAGE_PROVENANCE,
) -> dict[str, Any]:
    input_height, input_width = smart_resize(image_height, image_width)
    decoded, token_artifact_count = decode_token_artifacts(raw_text)
    cells, recovered_fragment = decode_layout_cells(decoded)
    warnings: list[str] = []
    malformed_count = 0
    duplicate_count = 0
    longest_duplicate_run = 0
    consecutive_duplicates = 0
    blocks: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()

    if token_artifact_count:
        warnings.append("Decoded byte-level tokenizer whitespace markers.")
    if recovered_fragment:
        warnings.append("Recovered layout JSON from surrounding model text.")

    if cells is None:
        malformed_count = 1
        warnings.append("Model output was not valid layout JSON; preserved it as plain text.")
        cells = [{"category": "Text", "text": decoded}]
        detection_count = 0
    else:
        detection_count = len(cells)

    for cell in cells:
        if not isinstance(cell, dict):
            malformed_count += 1
            continue
        raw_category = _text_value(
            _cell_value(cell, ("category", "type", "label"))
        ) or "Text"
        category = canonical_category(raw_category)
        text = _text_value(
            _cell_value(cell, ("text", "content", "markdown", "html"))
        )
        bbox_values = source_bbox(cell)
        has_bbox_field = any(
            key in cell for key in ("bbox", "bounding_box", "boundingBox", "box")
        )
        if has_bbox_field and bbox_values is None:
            malformed_count += 1
        if not text and category != "image":
            malformed_count += 1
            continue

        bbox_key = (
            tuple(round(value, 3) for value in bbox_values)
            if bbox_values is not None
            else None
        )
        collapsed_text = re.sub(r"\s+", " ", text).strip()
        signature = (category, bbox_key, collapsed_text)
        if signature in seen:
            duplicate_count += 1
            consecutive_duplicates += 1
            longest_duplicate_run = max(longest_duplicate_run, consecutive_duplicates)
            continue
        seen.add(signature)
        consecutive_duplicates = 0

        block: dict[str, Any] = {
            "id": f"page-{page_number}-block-{len(blocks) + 1}",
            "type": category,
            "sourceType": raw_category,
            "text": text,
            "html": text if category == "table" else None,
            "bbox": normalized_bbox(bbox_values, input_width, input_height)
            if bbox_values is not None
            else None,
            "sourceBbox": [round(value, 3) for value in bbox_values]
            if bbox_values is not None
            else None,
            # Dots emits pixel coordinates with independent x/y scales, while
            # the shared schema only has one optional scalar source scale.
            "sourceBboxScale": None,
        }
        blocks.append(block)

    if malformed_count:
        warnings.append(
            f"Ignored or repaired {malformed_count} malformed layout "
            f"element{'s' if malformed_count != 1 else ''}."
        )
    if duplicate_count:
        warnings.append(
            f"Removed {duplicate_count} duplicate layout "
            f"element{'s' if duplicate_count != 1 else ''}."
        )
    loop_detected = longest_duplicate_run >= 3 or duplicate_count >= 8
    if loop_detected:
        warnings.append("Truncated a repeated generation tail.")

    markdown_parts = [block_markdown(block) for block in blocks]
    markdown = "\n\n".join(part for part in markdown_parts if part).strip()
    plain_text = "\n".join(block["text"] for block in blocks if block["text"]).strip()
    if not blocks:
        raise ValueError(
            f"Dots OCR returned no usable layout blocks for page {page_number}."
        )
    return {
        "pageNumber": page_number,
        "imageFile": image_file,
        "markdown": markdown,
        "plainText": plain_text,
        "blocks": blocks,
        "provenance": provenance,
        "diagnostics": {
            "rawCharacterCount": len(raw_text),
            "decodedCharacterCount": len(decoded),
            "tokenArtifactCount": token_artifact_count,
            "detectionCount": detection_count,
            "malformedDetectionCount": malformed_count,
            "duplicateBlockCount": duplicate_count,
            "loopDetected": loop_detected,
            "warnings": warnings,
            "blockCount": len(blocks),
        },
    }


def document_payload(
    title: str,
    total_page_count: int,
    pages: list[dict[str, Any]],
    complete: bool,
    simulation: bool,
) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "object": "local_extraction",
        "provider": {
            "id": "dots-ocr",
            "name": "Dots OCR 1.5",
            "modelRepository": MODEL_REPOSITORY,
            "modelRevision": MODEL_REVISION,
            "runtimeLockVersion": RUNTIME_LOCK_VERSION,
        },
        "title": title,
        "pageCount": total_page_count,
        "completedPageCount": len(pages),
        "complete": complete,
        "simulation": simulation,
        "pages": pages,
    }


def persist_page(
    page_output_directory: Path,
    page_number: int,
    markdown: str,
    structured_page: dict[str, Any],
) -> None:
    write_atomic(
        page_output_directory / f"page-{page_number:04d}.md",
        markdown.rstrip("\n") + "\n",
    )
    write_atomic(
        page_output_directory / f"page-{page_number:04d}.json",
        json.dumps(structured_page, indent=2, sort_keys=True, ensure_ascii=False)
        + "\n",
    )


def load_persisted_page(
    page_output_directory: Path,
    page_number: int,
    expected_provenance: str = PAGE_PROVENANCE,
) -> dict[str, Any] | None:
    markdown_path = page_output_directory / f"page-{page_number:04d}.md"
    json_path = page_output_directory / f"page-{page_number:04d}.json"
    if not markdown_path.exists() or not json_path.exists():
        return None
    try:
        page = json.loads(json_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(page, dict) or page.get("provenance") != expected_provenance:
        return None
    return page


def persist_document_outputs(
    output: Path,
    structured_output: Path,
    page_output_directory: Path,
    header: str,
    title: str,
    total_page_count: int,
    pages: list[dict[str, Any]],
    simulation: bool,
) -> None:
    ordered_pages = sorted(pages, key=lambda page: int(page["pageNumber"]))
    markdown_sections = [
        (page_output_directory / f"page-{int(page['pageNumber']):04d}.md")
        .read_text(encoding="utf-8")
        .strip()
        for page in ordered_pages
    ]
    markdown = header.strip() + "\n\n"
    if markdown_sections:
        markdown += "\n\n".join(markdown_sections) + "\n"
    write_atomic(output, markdown)
    write_atomic(
        structured_output,
        json.dumps(
            document_payload(
                title,
                total_page_count,
                ordered_pages,
                complete=len(ordered_pages) == total_page_count,
                simulation=simulation,
            ),
            indent=2,
            sort_keys=True,
            ensure_ascii=False,
        )
        + "\n",
    )


def update_page_progress(
    progress_path: Path,
    page_number: int,
    status: str,
    completed_page_count: int,
) -> None:
    manifest = json.loads(progress_path.read_text(encoding="utf-8"))
    timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z"
    )
    manifest["updatedAt"] = timestamp
    manifest["completedPageCount"] = completed_page_count
    manifest["currentPageNumber"] = page_number
    manifest["currentPageStatus"] = status
    manifest["errorMessage"] = None
    if status == "succeeded":
        manifest["lastCompletedPageNumber"] = page_number
        manifest["lastCompletedAt"] = timestamp
    write_atomic(progress_path, json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def image_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as image_file:
        header = image_file.read(24)
    if len(header) >= 24 and header.startswith(b"\x89PNG\r\n\x1a\n"):
        width, height = struct.unpack(">II", header[16:24])
        if width > 0 and height > 0:
            return width, height
    raise ValueError(f"Dots OCR requires a valid rendered PNG page: {path}")


def simulated_layout(image_path: Path, width: int, height: int) -> str:
    return json.dumps(
        [
            {
                "bbox": [0, 0, width, max(1, round(height * 0.16))],
                "category": "Title",
                "text": "Dots OCR 1.5 simulation",
            },
            {
                "bbox": [
                    round(width * 0.08),
                    round(height * 0.24),
                    round(width * 0.92),
                    round(height * 0.8),
                ],
                "category": "Text",
                "text": f"Simulated local OCR for `{image_path.name}`.",
            },
        ],
        ensure_ascii=False,
    )


def main() -> None:
    args = parse_args()
    output = Path(args.output)
    page_output_directory = Path(args.page_output_directory)
    page_progress = Path(args.page_progress)
    structured_output = output.with_suffix(".json")
    page_output_directory.mkdir(parents=True, exist_ok=True)
    structured_pages: list[dict[str, Any]] = []
    simulation = bool(args.simulate)
    header_parts = [f"# {args.title}"]
    if simulation:
        header_parts.extend(
            [
                "> Simulation: Dots OCR 1.5 model weights were not loaded.",
                (
                    "Offline flags: "
                    f"HF_HUB_OFFLINE={os.environ.get('HF_HUB_OFFLINE', '')}, "
                    f"TRANSFORMERS_OFFLINE={os.environ.get('TRANSFORMERS_OFFLINE', '')}, "
                    f"HF_DATASETS_OFFLINE={os.environ.get('HF_DATASETS_OFFLINE', '')}."
                ),
            ]
        )
    header = "\n\n".join(header_parts)

    if not simulation:
        from mlx_vlm import generate, load
        from mlx_vlm.prompt_utils import apply_chat_template

        model, processor = load(args.model)
        formatted_prompt = apply_chat_template(
            processor,
            model.config,
            LAYOUT_PROMPT,
            num_images=1,
        )

    for page_number, image_name in enumerate(args.images, start=1):
        image_path = Path(image_name)
        expected_provenance = (
            SIMULATION_PAGE_PROVENANCE if simulation else PAGE_PROVENANCE
        )
        persisted_page = load_persisted_page(
            page_output_directory,
            page_number,
            expected_provenance=expected_provenance,
        )
        if persisted_page is not None:
            structured_pages.append(persisted_page)
            persist_document_outputs(
                output,
                structured_output,
                page_output_directory,
                header,
                args.title,
                len(args.images),
                structured_pages,
                simulation=simulation,
            )
            update_page_progress(
                page_progress,
                page_number,
                "succeeded",
                len(structured_pages),
            )
            print(f"Restored page {page_number} of {len(args.images)}", flush=True)
            continue

        update_page_progress(
            page_progress,
            page_number,
            "processing",
            len(structured_pages),
        )
        width, height = image_dimensions(image_path)
        if simulation:
            input_height, input_width = smart_resize(height, width)
            raw_text = simulated_layout(image_path, input_width, input_height)
        else:
            result = generate(
                model=model,
                processor=processor,
                prompt=formatted_prompt,
                image=image_name,
                max_tokens=16384,
                temperature=0.0,
            )
            raw_text = result.text if hasattr(result, "text") else str(result)

        structured_page = parse_model_output(
            raw_text,
            page_number=page_number,
            image_file=image_path.name,
            image_width=width,
            image_height=height,
            provenance=expected_provenance,
        )
        structured_pages.append(structured_page)
        section = f"## Page {page_number}\n\n{structured_page['markdown']}"
        persist_page(
            page_output_directory,
            page_number,
            section,
            structured_page,
        )
        persist_document_outputs(
            output,
            structured_output,
            page_output_directory,
            header,
            args.title,
            len(args.images),
            structured_pages,
            simulation=simulation,
        )
        update_page_progress(
            page_progress,
            page_number,
            "succeeded",
            len(structured_pages),
        )
        print(f"Processed page {page_number} of {len(args.images)}", flush=True)


if __name__ == "__main__":
    main()
