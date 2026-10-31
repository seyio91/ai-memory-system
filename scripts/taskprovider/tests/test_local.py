import shutil
import tempfile
import unittest
from pathlib import Path

from taskprovider.providers.local import FileTaskProvider


class LocalProviderTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        (self.root / "projects" / "alpha").mkdir(parents=True)
        self.provider = FileTaskProvider(self.root)

    def tearDown(self):
        shutil.rmtree(str(self.root))

    def test_lifecycle(self):
        ref = self.provider.capture("alpha", "Ship Local Provider", "initial summary")
        self.assertEqual([ref], [task.ref for task in self.provider.list("alpha", "backlog")])

        self.provider.update(ref, summary="updated summary")
        task = self.provider.get(ref)
        self.assertEqual("updated summary", task.summary)
        self.assertEqual("backlog", task.status)

        self.provider.set_status(ref, "started")
        self.assertEqual([], self.provider.list("alpha", "backlog"))
        self.assertEqual([ref], [task.ref for task in self.provider.list("alpha", "started")])

        self.provider.set_status(ref, "done")
        task = self.provider.get(ref)
        self.assertEqual("done", task.status)
        self.assertFalse((self.root / "tasks" / (ref + ".md")).exists())
        self.assertTrue((self.root / "archive" / "tasks" / (ref + ".md")).is_file())

        self.provider.set_status(ref, "archived")
        self.assertEqual([], self.provider.list("alpha", "done"))
        self.assertEqual([ref], [task.ref for task in self.provider.list("alpha", "archived")])
        self.assertFalse((self.root / "tasks" / (ref + ".md")).exists())
        self.assertTrue((self.root / "archive" / "tasks" / (ref + ".md")).is_file())

    def test_done_moves_file_to_archive(self):
        ref = self.provider.capture("alpha", "Finish", "summary")
        self.provider.set_status(ref, "done")
        archived = self.root / "archive" / "tasks" / (ref + ".md")
        self.assertFalse((self.root / "tasks" / (ref + ".md")).exists())
        self.assertTrue(archived.is_file())
        self.assertIn("status: done", archived.read_text(encoding="utf-8"))

    def test_done_to_archived_rewrites_in_place(self):
        ref = self.provider.capture("alpha", "Retire", "summary")
        self.provider.set_status(ref, "done")
        self.provider.set_status(ref, "archived")
        archived = self.root / "archive" / "tasks" / (ref + ".md")
        self.assertIn("status: archived", archived.read_text(encoding="utf-8"))
        self.assertFalse((self.root / "tasks" / (ref + ".md")).exists())
        self.assertEqual("archived", self.provider.get(ref).status)

    def test_reopen_moves_back_to_tasks(self):
        for closed in ("done", "archived"):
            for reopened in ("started", "backlog"):
                ref = self.provider.capture("alpha", "Reopen %s %s" % (closed, reopened), "summary")
                self.provider.set_status(ref, closed)
                self.provider.set_status(ref, reopened)
                self.assertTrue((self.root / "tasks" / (ref + ".md")).is_file())
                self.assertFalse((self.root / "archive" / "tasks" / (ref + ".md")).exists())
                self.assertEqual(reopened, self.provider.get(ref).status)

    def test_list_reads_directory_for_status(self):
        open_ref = self.provider.capture("alpha", "Open", "summary")
        started_ref = self.provider.capture("alpha", "Started", "summary")
        done_ref = self.provider.capture("alpha", "Done", "summary")
        archived_ref = self.provider.capture("alpha", "Archived", "summary")
        self.provider.set_status(started_ref, "started")
        self.provider.set_status(done_ref, "done")
        self.provider.set_status(archived_ref, "archived")
        refs = lambda status: [task.ref for task in self.provider.list("alpha", status)]
        self.assertEqual([open_ref], refs("backlog"))
        self.assertEqual([started_ref], refs("started"))
        self.assertEqual([done_ref], refs("done"))
        self.assertEqual([archived_ref], refs("archived"))

    def test_set_status_unknown_ref_raises(self):
        with self.assertRaises(ValueError):
            self.provider.set_status("does-not-exist", "done")

    def test_delete_ignores_done_task(self):
        ref = self.provider.capture("alpha", "Done", "summary")
        self.provider.set_status(ref, "done")
        with self.assertRaises(ValueError):
            self.provider.delete(ref)
        self.assertTrue((self.root / "archive" / "tasks" / (ref + ".md")).is_file())

    def test_update_closed_task(self):
        ref = self.provider.capture("alpha", "Closed Update", "summary")
        self.provider.set_status(ref, "done")
        self.provider.update(ref, summary="revised")
        self.assertEqual("revised", self.provider.get(ref).summary)
        self.assertTrue((self.root / "archive" / "tasks" / (ref + ".md")).is_file())

    def test_set_status_refuses_to_overwrite(self):
        ref = self.provider.capture("alpha", "Duplicate", "live")
        archive_dir = self.root / "archive" / "tasks"
        archive_dir.mkdir(parents=True)
        (archive_dir / (ref + ".md")).write_text("ARCHIVE COPY", encoding="utf-8")
        with self.assertRaises(ValueError):
            self.provider.set_status(ref, "done")
        self.assertEqual("ARCHIVE COPY", (archive_dir / (ref + ".md")).read_text(encoding="utf-8"))
        self.assertEqual("backlog", self.provider.get(ref).status)

    def test_delete_hard_removes_live_task(self):
        ref = self.provider.capture("alpha", "Delete Me", "summary")
        self.assertTrue((self.root / "tasks" / (ref + ".md")).is_file())

        self.provider.delete(ref)

        self.assertFalse((self.root / "tasks" / (ref + ".md")).exists())
        self.assertEqual([], self.provider.list("alpha", "backlog"))
        with self.assertRaises(ValueError):
            self.provider.get(ref)

    def test_delete_unknown_ref_raises(self):
        with self.assertRaises(ValueError):
            self.provider.delete("does-not-exist")

    def test_delete_ignores_archived_task(self):
        # delete acts on the live tasks/ file only; an archived task has been
        # moved to archive/tasks/ and must not be removed by delete.
        ref = self.provider.capture("alpha", "Archived", "summary")
        self.provider.set_status(ref, "archived")
        with self.assertRaises(ValueError):
            self.provider.delete(ref)
        self.assertTrue((self.root / "archive" / "tasks" / (ref + ".md")).is_file())

    def test_get_round_trips_every_field(self):
        ref = self.provider.capture("alpha", "Round Trip", "body\nline 2")
        task = self.provider.get(ref)
        self.assertEqual(ref, task.ref)
        self.assertEqual("alpha", task.project)
        self.assertEqual("Round Trip", task.title)
        self.assertEqual("body\nline 2", task.summary)
        self.assertEqual("backlog", task.status)
        self.assertRegex(task.created, r"^\d{4}-\d{2}-\d{2}$")


if __name__ == "__main__":
    unittest.main()
