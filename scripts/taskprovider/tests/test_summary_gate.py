import shutil
import tempfile
import unittest
from pathlib import Path

from taskprovider.contract import SUMMARY_MAX_CHARS
from taskprovider.providers.local import FileTaskProvider
from taskprovider.providers.notion import NotionProvider


LONG_SUMMARY = "x" * (SUMMARY_MAX_CHARS + 1)
MAX_SUMMARY = "x" * SUMMARY_MAX_CHARS
ERROR_MESSAGE = (
    "summary is 501 chars; maximum is 500. Write long-form content to "
    "projects/<project>/brainstorms/<slug>.md and reference it by path "
    "from the summary."
)


class SummaryGateTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / "projects" / "alpha").mkdir(parents=True)
        self.local = FileTaskProvider(self.root)

    def tearDown(self):
        shutil.rmtree(str(self.root))

    def test_local_capture_rejects_over_cap_summary_before_write(self):
        with self.assertRaises(ValueError) as ctx:
            self.local.capture("alpha", "Too Long", LONG_SUMMARY)

        self.assertEqual(ERROR_MESSAGE, str(ctx.exception))
        self.assertFalse((self.root / "tasks").exists())

    def test_notion_capture_rejects_over_cap_summary_before_request(self):
        provider = NotionProvider()

        def fail_request(method, url, body=None):
            self.fail("Notion request should not be called")

        provider._request = fail_request

        with self.assertRaises(ValueError) as ctx:
            provider.capture("alpha", "Too Long", LONG_SUMMARY)

        self.assertEqual(ERROR_MESSAGE, str(ctx.exception))

    def test_update_rejects_over_cap_summary_but_allows_title_only(self):
        ref = self.local.capture("alpha", "Short", "short")

        with self.assertRaises(ValueError) as ctx:
            self.local.update(ref, summary=LONG_SUMMARY)
        self.assertEqual(ERROR_MESSAGE, str(ctx.exception))

        self.local.update(ref, title="Renamed")
        task = self.local.get(ref)
        self.assertEqual("Renamed", task.title)
        self.assertEqual("short", task.summary)

    def test_summary_boundary(self):
        ref = self.local.capture("alpha", "Boundary", MAX_SUMMARY)
        self.assertEqual(MAX_SUMMARY, self.local.get(ref).summary)

        with self.assertRaises(ValueError):
            self.local.capture("alpha", "Too Long", LONG_SUMMARY)

    def test_legacy_over_cap_summary_reads_via_get_and_list(self):
        tasks_dir = self.root / "tasks"
        tasks_dir.mkdir(parents=True)
        path = tasks_dir / "legacy.md"
        path.write_text(
            "\n".join([
                "---",
                "project: alpha",
                "status: backlog",
                "created: 2026-07-09",
                "title: Legacy",
                "---",
                LONG_SUMMARY,
            ]),
            encoding="utf-8",
        )

        self.assertEqual(LONG_SUMMARY, self.local.get("legacy").summary)
        tasks = self.local.list("alpha", "backlog")
        self.assertEqual([LONG_SUMMARY], [task.summary for task in tasks])


if __name__ == "__main__":
    unittest.main()
