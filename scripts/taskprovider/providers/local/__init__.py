import datetime
import os
import re
import shutil
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
        ref = self._unique_ref(self._slug(title), tasks_dir)
        created = datetime.date.today().isoformat()
        self._write_task(tasks_dir / (ref + ".md"), {
            "project": project,
            "status": "backlog",
            "created": created,
            "title": title,
        }, summary)
        return ref

    def list(self, project, status):
        self.resolve_project(project)
        tasks_dir = self._dir_for(status)
        if not tasks_dir.is_dir():
            return []
        tasks = []
        for path in sorted(tasks_dir.glob("*.md")):
            task = self._read_task(path)
            if task.project == project and task.status == status:
                tasks.append(task)
        return tasks

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
            shutil.move(str(path), str(target))
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

    def _write_task(self, path, fields, body):
        path.parent.mkdir(parents=True, exist_ok=True)
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
        path.write_text("\n".join(content), encoding="utf-8")

    def _slug(self, title):
        slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
        return slug or "task"

    def _unique_ref(self, base, tasks_dir):
        ref = base
        number = 2
        while (tasks_dir / (ref + ".md")).exists() or (self.root / "archive" / "tasks" / (ref + ".md")).exists():
            ref = "%s-%d" % (base, number)
            number += 1
        return ref


PROVIDER = FileTaskProvider
