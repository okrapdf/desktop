import importlib.util
import json
import struct
import subprocess
import sys
import tempfile
import types
import unittest
import zlib
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


def worker_path():
    return (
        Path(__file__).resolve().parents[2]
        / "OkraPDF"
        / "ProviderScripts"
        / "dots-ocr-worker.py"
    )


def load_worker_module():
    spec = importlib.util.spec_from_file_location("dots_ocr_worker", worker_path())
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def png_chunk(kind, data):
    checksum = zlib.crc32(kind)
    checksum = zlib.crc32(data, checksum) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", checksum)


def write_png(path, width, height):
    rows = b"".join(b"\x00" + (b"\xff\xff\xff" * width) for _ in range(height))
    contents = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(
            b"IHDR",
            struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0),
        )
        + png_chunk(b"IDAT", zlib.compress(rows))
        + png_chunk(b"IEND", b"")
    )
    path.write_bytes(contents)


worker = load_worker_module()


class DotsOCROutputParserTests(unittest.TestCase):
    def test_official_layout_prompt_and_mlx_generation_contract(self):
        calls = {}
        fake_model = SimpleNamespace(config=object())
        fake_processor = object()

        def fake_load(model_path):
            calls["model_path"] = model_path
            return fake_model, fake_processor

        def fake_apply_chat_template(processor, config, prompt, **kwargs):
            calls["template"] = (processor, config, prompt, kwargs)
            return "formatted prompt"

        def fake_generate(**kwargs):
            calls["generate"] = kwargs
            return SimpleNamespace(
                text='[{"bbox":[0,0,320,160],"category":"Text","text":"Parsed"}]'
            )

        mlx_module = types.ModuleType("mlx_vlm")
        mlx_module.generate = fake_generate
        mlx_module.load = fake_load
        prompt_module = types.ModuleType("mlx_vlm.prompt_utils")
        prompt_module.apply_chat_template = fake_apply_chat_template

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / "page-0001.png"
            write_png(image, width=320, height=160)
            progress = root / "page-progress.json"
            progress.write_text(
                json.dumps({"schemaVersion": 1, "totalPages": 1, "completedPageCount": 0})
            )
            args = SimpleNamespace(
                model=str(root / "model"),
                output=str(root / "result.md"),
                page_output_directory=str(root / "page-results"),
                page_progress=str(progress),
                title="sample.pdf",
                images=[str(image)],
                simulate=False,
            )
            with patch.dict(
                sys.modules,
                {"mlx_vlm": mlx_module, "mlx_vlm.prompt_utils": prompt_module},
            ), patch.object(worker, "parse_args", return_value=args), patch(
                "builtins.print"
            ):
                worker.main()

        self.assertEqual(calls["model_path"], args.model)
        processor, config, prompt, template_kwargs = calls["template"]
        self.assertIs(processor, fake_processor)
        self.assertIs(config, fake_model.config)
        self.assertEqual(prompt, worker.LAYOUT_PROMPT)
        self.assertIn("All layout elements must be sorted", prompt)
        self.assertEqual(template_kwargs, {"num_images": 1})
        self.assertEqual(
            calls["generate"],
            {
                "model": fake_model,
                "processor": fake_processor,
                "prompt": "formatted prompt",
                "image": str(image),
                "max_tokens": 16384,
                "temperature": 0.0,
            },
        )

    def test_parses_layout_array_in_smart_resized_model_coordinate_space(self):
        raw = """```json
[
  {"bbox": [100, 50, 900, 450], "category": "Title", "text": "Quarterly report"},
  {"bbox": [120, 480, 880, 650], "category": "Section-header", "text": "Results"},
  {"bbox": [100, 700, 900, 850], "category": "Table", "text": "<table><tr><td>$49</td></tr></table>"},
  {"bbox": [200, 870, 800, 930], "category": "Formula", "text": "E = mc^2"},
  {"bbox": [0, 940, 1000, 1000], "category": "Picture"}
]
```"""

        page = worker.parse_model_output(
            raw,
            page_number=1,
            image_file="page-0001.png",
            image_width=1000,
            image_height=1000,
        )

        self.assertEqual(worker.smart_resize(1000, 1000), (1008, 1008))
        self.assertEqual([block["type"] for block in page["blocks"]], [
            "title",
            "heading",
            "table",
            "equation",
            "image",
        ])
        self.assertEqual(
            page["blocks"][0]["bbox"],
            {
                "x": 0.099206,
                "y": 0.049603,
                "width": 0.793651,
                "height": 0.396825,
                "unit": "normalized",
                "origin": "top-left",
            },
        )
        self.assertIsNone(page["blocks"][0]["sourceBboxScale"])
        self.assertEqual(
            page["blocks"][2]["html"],
            "<table><tr><td>$49</td></tr></table>",
        )
        self.assertIn("$$\nE = mc^2\n$$", page["markdown"])
        self.assertEqual(page["blocks"][4]["text"], "")
        self.assertEqual(page["diagnostics"]["detectionCount"], 5)
        self.assertEqual(page["diagnostics"]["malformedDetectionCount"], 0)

    def test_recovers_wrapped_json_and_clamps_reversed_pixel_coordinates(self):
        raw = "Model result follows:\n" + json.dumps(
            {
                "layout": [
                    {
                        "bounding_box": ["1200", "220", "-10", "20"],
                        "type": "Page-header",
                        "content": "Confidential",
                    }
                ]
            }
        ) + "\nEnd of result."

        page = worker.parse_model_output(
            raw,
            page_number=2,
            image_file="page-0002.png",
            image_width=1000,
            image_height=200,
        )

        self.assertEqual(page["blocks"][0]["type"], "header")
        self.assertEqual(
            page["blocks"][0]["bbox"],
            {
                "x": 0.0,
                "y": 0.102041,
                "width": 1.0,
                "height": 0.897959,
                "unit": "normalized",
                "origin": "top-left",
            },
        )
        self.assertIn("Recovered layout JSON", " ".join(page["diagnostics"]["warnings"]))

    def test_repairs_malformed_cells_and_removes_duplicate_tail(self):
        repeated = {
            "bbox": [10, 20, 100, 40],
            "category": "List-item",
            "text": "One",
        }
        raw = json.dumps(
            [
                {"bbox": [0, "nope", 10, 20], "category": "Text", "text": "Kept"},
                "not an object",
                repeated,
                repeated,
                repeated,
                repeated,
            ]
        )

        page = worker.parse_model_output(
            raw,
            page_number=1,
            image_file="page-0001.png",
            image_width=200,
            image_height=100,
        )

        self.assertEqual(len(page["blocks"]), 2)
        self.assertIsNone(page["blocks"][0]["bbox"])
        self.assertEqual(page["blocks"][1]["type"], "list-item")
        self.assertEqual(page["diagnostics"]["malformedDetectionCount"], 2)
        self.assertEqual(page["diagnostics"]["duplicateBlockCount"], 3)
        self.assertTrue(page["diagnostics"]["loopDetected"])

    def test_invalid_json_is_preserved_as_plain_text(self):
        page = worker.parse_model_output(
            "Recognized text without a JSON envelope",
            page_number=1,
            image_file="page-0001.png",
            image_width=100,
            image_height=100,
        )

        self.assertEqual(page["plainText"], "Recognized text without a JSON envelope")
        self.assertEqual(page["blocks"][0]["type"], "text")
        self.assertEqual(page["blocks"][0]["bbox"], None)
        self.assertEqual(page["diagnostics"]["detectionCount"], 0)
        self.assertGreater(page["diagnostics"]["malformedDetectionCount"], 0)

    def test_empty_layout_is_a_page_failure(self):
        with self.assertRaisesRegex(
            ValueError,
            "no usable layout blocks for page 3",
        ):
            worker.parse_model_output(
                "[]",
                page_number=3,
                image_file="page-0003.png",
                image_width=100,
                image_height=100,
            )

    def test_structured_document_and_persisted_page_round_trip(self):
        page = worker.parse_model_output(
            '[{"bbox":[0,0,400,200],"category":"Text","text":"Parsed"}]',
            page_number=1,
            image_file="page-0001.png",
            image_width=400,
            image_height=200,
        )

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pages = root / "page-results"
            worker.persist_page(pages, 1, "## Page 1\n\nParsed", page)
            restored = worker.load_persisted_page(pages, 1)
            worker.persist_document_outputs(
                root / "result.md",
                root / "result.json",
                pages,
                "# sample.pdf",
                "sample.pdf",
                total_page_count=1,
                pages=[restored],
                simulation=False,
            )
            payload = json.loads((root / "result.json").read_text())

        self.assertEqual(payload["provider"]["id"], "dots-ocr")
        self.assertEqual(payload["provider"]["name"], "Dots OCR 1.5")
        self.assertEqual(payload["provider"]["modelRevision"], worker.MODEL_REVISION)
        self.assertEqual(
            payload["provider"]["runtimeLockVersion"],
            worker.RUNTIME_LOCK_VERSION,
        )
        self.assertTrue(payload["complete"])
        self.assertEqual(payload["pages"][0]["blocks"][0]["bbox"]["width"], 1.0)

    def test_checkpoint_restore_requires_matching_model_and_runtime_provenance(self):
        page = worker.parse_model_output(
            '[{"category":"Text","text":"Old result"}]',
            page_number=1,
            image_file="page-0001.png",
            image_width=100,
            image_height=100,
        )

        with tempfile.TemporaryDirectory() as directory:
            pages = Path(directory)
            worker.persist_page(pages, 1, "## Page 1\n\nOld result", page)
            restored = worker.load_persisted_page(pages, 1)
            rejected = worker.load_persisted_page(
                pages,
                1,
                expected_provenance="dots-ocr:model=future-revision;runtime=v2",
            )

        self.assertIsNotNone(restored)
        self.assertIsNone(rejected)

    def test_simulation_uses_png_dimensions_and_restores_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / "page-0001.png"
            output = root / "result.md"
            pages = root / "page-results"
            progress = root / "page-progress.json"
            write_png(image, width=400, height=200)
            progress.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "totalPages": 1,
                        "completedPageCount": 0,
                    }
                )
            )
            command = [
                sys.executable,
                str(worker_path()),
                "--model",
                str(root / "unused-model"),
                "--output",
                str(output),
                "--page-output-directory",
                str(pages),
                "--page-progress",
                str(progress),
                "--title",
                "sample.pdf",
                "--images",
                str(image),
                "--simulate",
            ]

            first = subprocess.run(command, check=True, capture_output=True, text=True)
            second = subprocess.run(command, check=True, capture_output=True, text=True)
            payload = json.loads(output.with_suffix(".json").read_text())
            manifest = json.loads(progress.read_text())

        self.assertIn("Processed page 1 of 1", first.stdout)
        self.assertIn("Restored page 1 of 1", second.stdout)
        self.assertEqual(payload["provider"]["id"], "dots-ocr")
        self.assertTrue(payload["simulation"])
        self.assertEqual(
            payload["pages"][0]["provenance"],
            worker.SIMULATION_PAGE_PROVENANCE,
        )
        self.assertEqual(payload["pages"][0]["blocks"][0]["bbox"]["width"], 1.0)
        self.assertEqual(
            payload["pages"][0]["blocks"][0]["sourceBbox"],
            [0.0, 0.0, 392.0, 31.0],
        )
        self.assertEqual(manifest["completedPageCount"], 1)
        self.assertEqual(manifest["currentPageStatus"], "succeeded")


if __name__ == "__main__":
    unittest.main()
