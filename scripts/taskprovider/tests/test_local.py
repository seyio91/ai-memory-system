import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

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

    def test_capture_collision_takes_next_suffix(self):
        tasks_dir = self.root / "tasks"
        tasks_dir.mkdir(parents=True)
        winner = tasks_dir / "race.md"
        real_link = os.link

        def racing_link(src, dst, *args, **kwargs):
            # The winner appears after any exists() check, right before publish.
            if not winner.exists():
                winner.write_bytes(b"WINNER CONTENT")
            return real_link(src, dst, *args, **kwargs)

        with mock.patch.object(Path, "exists", return_value=False), \
                mock.patch("os.link", side_effect=racing_link):
            ref = self.provider.capture("alpha", "Race", "loser")
        self.assertEqual("race-2", ref)
        self.assertEqual(b"WINNER CONTENT", winner.read_bytes())
        self.assertEqual("loser", self.provider.get("race-2").summary)
        self.assertEqual(["race-2.md", "race.md"], sorted(os.listdir(str(tasks_dir))))

    def test_capture_skips_archived_ref(self):
        archive_dir = self.root / "archive" / "tasks"
        archive_dir.mkdir(parents=True)
        (archive_dir / "old.md").write_text("x", encoding="utf-8")
        self.assertEqual("old-2", self.provider.capture("alpha", "Old", "s"))

    def test_capture_never_exposes_partial_md(self):
        tasks_dir = self.root / "tasks"
        seen = []
        real_link = os.link

        def snapshot_link(src, dst, *args, **kwargs):
            for path in tasks_dir.glob("*.md"):
                seen.append(path)
                self.provider._read_task(path)  # raises on a stub
            return real_link(src, dst, *args, **kwargs)

        with mock.patch("os.link", side_effect=snapshot_link):
            self.provider.capture("alpha", "First", "one")
            self.provider.capture("alpha", "Second", "two")
        self.assertEqual(1, len(seen))  # only First visible while publishing Second
        for path in tasks_dir.glob("*.md"):
            self.assertGreater(path.stat().st_size, 0)
            self.provider._read_task(path)

    def test_capture_failure_before_publish_leaves_nothing(self):
        with mock.patch("os.link", side_effect=OSError("boom")):
            with self.assertRaises(OSError):
                self.provider.capture("alpha", "Stub", "x")
        self.assertEqual([], os.listdir(str(self.root / "tasks")))
        with mock.patch("os.fsync", side_effect=OSError("boom")):
            with self.assertRaises(OSError):
                self.provider.capture("alpha", "Stub", "x")
        self.assertEqual([], os.listdir(str(self.root / "tasks")))

    def test_failed_write_leaves_original_and_no_temp_files(self):
        ref = self.provider.capture("alpha", "Atomic", "original")
        path = self.root / "tasks" / (ref + ".md")
        before = path.read_bytes()
        with mock.patch("os.replace", side_effect=OSError("boom")):
            with self.assertRaises(OSError):
                self.provider.update(ref, summary="changed")
        self.assertEqual(before, path.read_bytes())
        self.assertEqual([path.name], sorted(os.listdir(str(path.parent))))

    def test_set_status_rename_failure_leaves_one_copy_and_retry_completes(self):
        ref = self.provider.capture("alpha", "Half", "body")
        src = self.root / "tasks" / (ref + ".md")
        target = self.root / "archive" / "tasks" / (ref + ".md")
        with mock.patch("os.rename", side_effect=OSError("boom")):
            with self.assertRaises(OSError):
                self.provider.set_status(ref, "done")
        self.assertTrue(src.is_file())
        self.assertFalse(target.exists())
        self.assertEqual("body", self.provider.get(ref).summary)
        self.assertEqual([], self.provider.list("alpha", "backlog"))
        self.assertEqual([ref], [t.ref for t in self.provider.list("alpha", "done")])
        self.provider.set_status(ref, "done")
        self.assertFalse(src.exists())
        self.assertEqual("done", self.provider.get(ref).status)
        self.assertEqual([ref], [t.ref for t in self.provider.list("alpha", "done")])
        self.assertEqual([ref + ".md"], os.listdir(str(target.parent)))

    def test_max_length_filename_task_stays_writable(self):
        ref = self.provider.capture("alpha", "a" * 252, "body")
        self.assertEqual(255, len(ref + ".md"))
        self.provider.update(ref, summary="two")
        self.provider.set_status(ref, "done")
        self.provider.set_status(ref, "archived")
        self.assertEqual("two", self.provider.get(ref).summary)

    def test_archiving_keeps_restrictive_mode(self):
        ref = self.provider.capture("alpha", "Private", "secret")
        os.chmod(str(self.root / "tasks" / (ref + ".md")), 0o600)
        self.provider.set_status(ref, "done")
        target = self.root / "archive" / "tasks" / (ref + ".md")
        self.assertEqual(0o600, target.stat().st_mode & 0o777)

    def test_write_failure_does_not_leak_fd_or_temp(self):
        ref = self.provider.capture("alpha", "Leak", "body")
        before = len(os.listdir("/dev/fd"))
        for target in ("os.fchmod", "os.fsync"):
            with mock.patch(target, side_effect=OSError("boom")):
                with self.assertRaises(OSError):
                    self.provider.update(ref, summary="changed")
        self.assertEqual(before, len(os.listdir("/dev/fd")))
        self.assertEqual([ref + ".md"], os.listdir(str(self.root / "tasks")))

    def test_writes_keep_umask_or_existing_mode(self):
        old = os.umask(0o022)
        try:
            ref = self.provider.capture("alpha", "Mode", "summary")
        finally:
            os.umask(old)
        path = self.root / "tasks" / (ref + ".md")
        self.assertEqual(0o644, path.stat().st_mode & 0o777)
        os.chmod(str(path), 0o640)
        self.provider.update(ref, summary="changed")
        self.assertEqual(0o640, path.stat().st_mode & 0o777)

    def test_no_umask_calls_in_write_paths(self):
        with mock.patch("os.umask", side_effect=AssertionError("umask called")):
            ref = self.provider.capture("alpha", "NoUmask", "s")
            self.provider.update(ref, summary="t")
            self.provider.set_status(ref, "done")
            self.provider.set_status(ref, "archived")

    def test_list_ignores_malformed_file_in_other_dir(self):
        ref = self.provider.capture("alpha", "Good", "s")
        bad = self.root / "archive" / "tasks"
        bad.mkdir(parents=True)
        (bad / "broken.md").write_text("not frontmatter")
        self.assertEqual([ref], [t.ref for t in self.provider.list("alpha", "backlog")])

    def test_list_malformed_file_in_home_dir_still_errors(self):
        self.provider.capture("alpha", "Good", "s")
        (self.root / "tasks" / "broken.md").write_text("not frontmatter")
        with self.assertRaises(ValueError):
            self.provider.list("alpha", "backlog")

    def test_list_same_ref_in_both_dirs_prefers_matching_status(self):
        ref = self.provider.capture("alpha", "Dup", "s")
        live = self.root / "tasks" / (ref + ".md")
        arch = self.root / "archive" / "tasks"
        arch.mkdir(parents=True)
        text = live.read_text()
        (arch / (ref + ".md")).write_text(text.replace("status: backlog", "status: done"))
        self.assertEqual("done", self.provider.list("alpha", "done")[0].status)
        self.assertEqual("backlog", self.provider.list("alpha", "backlog")[0].status)


if __name__ == "__main__":
    unittest.main()
