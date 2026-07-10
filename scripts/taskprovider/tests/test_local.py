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
        self.assertTrue((self.root / "tasks" / (ref + ".md")).is_file())

        self.provider.set_status(ref, "archived")
        self.assertEqual([], self.provider.list("alpha", "done"))
        self.assertFalse((self.root / "tasks" / (ref + ".md")).exists())
        self.assertTrue((self.root / "archive" / "tasks" / (ref + ".md")).is_file())

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
