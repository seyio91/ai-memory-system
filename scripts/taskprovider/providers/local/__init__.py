import datetime
import os
import re
import secrets
import stat
from pathlib import Path

from taskprovider.contract import CANONICAL_STATUSES, Task, TaskProvider


class FileTaskProvider(TaskProvider):
    @property
    def status_map(self):
        return {status: status for status in CANONICAL_STATUSES}

    def __init__(self, root=None):
        self.root = Path(root or os.environ.get("MEMORY_DIR", Path(__file__).resolve().parents[4]))

    def resolve_project(self, name):
        path = self.root / "projects" / name
        if not path.is_dir():
            raise ValueError("unknown project %r under %s" % (name, self.root / "projects"))
        return name

    def capture(self, project, title, summary):
        project = self.resolve_project(project)
        tasks_dir = self.root / "tasks"
        tasks_dir.mkdir(parents=True, exist_ok=True)
        created = datetime.date.today().isoformat()
        content = self._render({
            "project": project,
            "status": "backlog",
            "created": created,
            "title": title,
        }, summary)
        # Build the full file in a hidden temp (".tmp" suffix: never matches the
        # *.md globs readers use), then publish it with os.link: an atomic
        # exclusive create that is complete from the instant it is visible.
        tmp = self._write_temp(tasks_dir, content)
        try:
            return self._publish(self._slug(title), tasks_dir, tmp)
        finally:
            try:
                os.unlink(tmp)
            except OSError:
                pass

    def list(self, project, status):
        self.resolve_project(project)
        # Scan both live dirs and trust the recorded status: an interrupted
        # set_status can leave a task whose status is ahead of its directory.
        # The status's home dir is validated strictly; the other dir leniently.
        home = self._dir_for(status)
        found = {}
        for directory in (self.root / "tasks", self.root / "archive" / "tasks"):
            if not directory.is_dir():
                continue
            for path in directory.glob("*.md"):
                if directory == home:
                    task = self._read_task(path)
                else:
                    try:
                        task = self._read_task(path)
                    except (ValueError, OSError, UnicodeDecodeError):
                        continue
                prior = found.get(path.name)
                if prior is None or (prior.status != status and task.status == status):
                    found[path.name] = task
        return [found[name] for name in sorted(found)
                if found[name].project == project and found[name].status == status]

    def get(self, ref):
        path = self.root / "tasks" / (ref + ".md")
        if not path.is_file():
            archive_path = self.root / "archive" / "tasks" / (ref + ".md")
            if archive_path.is_file():
                path = archive_path
            else:
                raise ValueError("unknown task ref %r" % ref)
        return self._read_task(path)

    def update(self, ref, *, title=None, summary=None):
        path = self._find_path(ref)
        fields, body = self._parse(path)
        if title is not None:
            fields["title"] = title
        if summary is not None:
            body = summary
        self._write_task(path, fields, body)

    def set_status(self, ref, status):
        path = self._find_path(ref)
        fields, body = self._parse(path)
        fields["status"] = status
        target = self._dir_for(status) / path.name
        if target != path:
            if target.exists():
                raise ValueError("task ref %r exists in both %s and %s" % (ref, path.parent, target.parent))
            target.parent.mkdir(parents=True, exist_ok=True)
            # Rewrite the source in place first (atomic, keeps its mode), then
            # rename it across: an interruption leaves exactly one file, which
            # a retry of set_status completes. rename keeps inode and mode.
            self._write_task(path, fields, body)
            os.rename(str(path), str(target))
        else:
            self._write_task(target, fields, body)

    def delete(self, ref):
        # Hard delete of the live task file (decision A). archive/tasks/ already
        # covers "retire but keep" via set_status(archived); delete removes.
        # _live_path raises on unknown/absent-or-archived refs, so delete fails
        # loudly rather than silently succeeding.
        self._live_path(ref).unlink()

    def ping(self):
        return True

    def _live_path(self, ref):
        path = self.root / "tasks" / (ref + ".md")
        if not path.is_file():
            raise ValueError("unknown live task ref %r" % ref)
        return path

    def _find_path(self, ref):
        for directory in (self.root / "tasks", self.root / "archive" / "tasks"):
            path = directory / (ref + ".md")
            if path.is_file():
                return path
        raise ValueError("unknown task ref %r" % ref)

    def _dir_for(self, status):
        if status in ("done", "archived"):
            return self.root / "archive" / "tasks"
        return self.root / "tasks"

    def _read_task(self, path):
        fields, body = self._parse(path)
        missing = [key for key in ("project", "title", "status", "created") if not fields.get(key)]
        if missing:
            raise ValueError("%s missing fields: %s" % (path, ", ".join(missing)))
        return Task(
            ref=path.stem,
            project=fields["project"],
            title=fields["title"],
            summary=body,
            status=fields["status"],
            created=fields["created"],
        )

    def _parse(self, path):
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        if not lines or lines[0].strip() != "---":
            raise ValueError("%s missing frontmatter" % path)
        fields = {}
        end = None
        for index, line in enumerate(lines[1:], 1):
            if line.strip() == "---":
                end = index
                break
            match = re.match(r"^([^:]+):[ \t]*(.*)$", line)
            if match:
                fields[match.group(1)] = match.group(2).rstrip()
        if end is None:
            raise ValueError("%s missing frontmatter close" % path)
        body = "\n".join(lines[end + 1:])
        if text.endswith("\n") and body:
            body += "\n"
        return fields, body

    def _render(self, fields, body):
        ordered = []
        for key in ("project", "status", "created", "title"):
            if key in fields:
                ordered.append((key, fields[key]))
        for key in fields:
            if key not in ("project", "status", "created", "title"):
                ordered.append((key, fields[key]))
        content = ["---"]
        content.extend("%s: %s" % (key, value) for key, value in ordered)
        content.append("---")
        content.append(body or "")
        return "\n".join(content)

    def _write_temp(self, directory, content, mode=None):
        # Durable temp file in `directory`; returns its path. Removed on failure.
        # Created 0666 so the kernel applies the umask (no process-global umask
        # probing); `mode` (an existing file's mode) is fchmod'd over it.
        directory.mkdir(parents=True, exist_ok=True)
        while True:
            tmp = str(directory / (".tmp-" + secrets.token_hex(8) + ".tmp"))
            try:
                fd = os.open(tmp, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o666)
                break
            except FileExistsError:
                continue
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                if mode is not None:
                    os.fchmod(handle.fileno(), mode)
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
        return tmp

    def _write_task(self, path, fields, body):
        # Keep the existing file's mode; a new file gets the umask default.
        mode = stat.S_IMODE(os.stat(str(path)).st_mode) if path.exists() else None
        tmp = self._write_temp(path.parent, self._render(fields, body), mode)
        try:
            os.replace(tmp, str(path))
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise

    def _slug(self, title):
        slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
        return slug or "task"

    def _publish(self, base, tasks_dir, tmp):
        # Publish the finished temp as tasks/<ref>.md via os.link, which fails
        # with FileExistsError instead of overwriting, so concurrent captures
        # can never pick the same ref. Archived refs are skipped too.
        archive_dir = self.root / "archive" / "tasks"
        ref = base
        number = 2
        while True:
            if not (archive_dir / (ref + ".md")).exists():
                try:
                    os.link(tmp, str(tasks_dir / (ref + ".md")))
                    return ref
                except FileExistsError:
                    pass
            ref = "%s-%d" % (base, number)
            number += 1


PROVIDER = FileTaskProvider
