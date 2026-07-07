import json
import os
import re
import urllib.error
import urllib.request

from taskprovider.contract import Task, TaskProvider

_UUID_RE = re.compile(r"\A[0-9a-fA-F]{32}\Z")


def _require_full_ref(ref):
    """Guard: a Notion ref must be a full page UUID (32 hex, dashes optional).

    A short prefix (e.g. the 8-char abbreviation humans sometimes jot in notes)
    is ambiguous — several pages can share it — and the API rejects it with an
    opaque 400. Fail early with an actionable message so callers always pass the
    full ref returned by ``capture`` / ``list`` / ``get``.
    """
    compact = (ref or "").replace("-", "")
    if not _UUID_RE.match(compact):
        raise ValueError(
            "Notion ref must be a full page UUID (32 hex, dashes optional), got "
            "%r — short ids are ambiguous and rejected by the API; use the "
            "full ref from `taskctl list` / `get`." % ref
        )
    return ref


class NotionProvider(TaskProvider):
    API_ROOT = "https://api.notion.com/v1"
    VERSION = "2025-09-03"
    DATA_SOURCE_ENV = "NOTION_DATA_SOURCE_ID"
    TOKEN_ENV = "NOTION_TOKEN"

    NAME_PROP = "Name"
    SUMMARY_PROP = "Summary"
    PROJECT_PROP = "Project"
    STATUS_PROP = "Status"
    CLAUDE_PROP = "Claude"
    CREATED_PROP = "Created"

    @property
    def status_map(self):
        return {
            "backlog": "Backlog",
            "started": "In-progress",
            "done": "Done",
            "archived": "Archived",
        }

    def __init__(self):
        self.token = os.environ.get(self.TOKEN_ENV)
        self.data_source_id = os.environ.get(self.DATA_SOURCE_ENV)
        # Status can be a Notion "status"-type property (default) or a plain
        # "select" — boards differ. The native value shape and the query filter
        # key both follow this. Read shape is type-agnostic (handles both).
        self.status_kind = os.environ.get("NOTION_STATUS_KIND", "status")

    def resolve_project(self, name):
        if not name or not name.strip():
            raise ValueError("project name must not be empty")
        return name

    def capture(self, project, title, summary):
        project = self.resolve_project(project)
        body = {
            "parent": {
                "type": "data_source_id",
                "data_source_id": self._data_source_id(),
            },
            "properties": {
                self.NAME_PROP: self._title_value(title),
                self.SUMMARY_PROP: self._text_value(summary),
                self.PROJECT_PROP: self._text_value(project),
                self.STATUS_PROP: self._status_value(self.status_map["backlog"]),
                self.CLAUDE_PROP: {"checkbox": True},
            },
        }
        page = self._request("POST", self.API_ROOT + "/pages", body)
        ref = page.get("id")
        if not ref:
            raise ValueError("Notion create response missing page id")
        return ref

    def list(self, project, status):
        project = self.resolve_project(project)
        native_status = self.status_map[status]
        body = {
            "filter": {
                "and": [
                    {"property": self.CLAUDE_PROP, "checkbox": {"equals": True}},
                    {"property": self.PROJECT_PROP, "rich_text": {"equals": project}},
                    {"property": self.STATUS_PROP, self.status_kind: {"equals": native_status}},
                ]
            },
            "page_size": 100,
        }
        response = self._request(
            "POST",
            self.API_ROOT + "/data_sources/" + self._data_source_id() + "/query",
            body,
        )
        return [self._task_from_page(page) for page in response.get("results", [])]

    def get(self, ref):
        _require_full_ref(ref)
        return self._task_from_page(self._request("GET", self.API_ROOT + "/pages/" + ref))

    def update(self, ref, *, title=None, summary=None):
        _require_full_ref(ref)
        properties = {}
        if title is not None:
            properties[self.NAME_PROP] = self._title_value(title)
        if summary is not None:
            properties[self.SUMMARY_PROP] = self._text_value(summary)
        self._request("PATCH", self.API_ROOT + "/pages/" + ref, {"properties": properties})

    def set_status(self, ref, status):
        _require_full_ref(ref)
        body = {
            "properties": {
                self.STATUS_PROP: self._status_value(self.status_map[status]),
            }
        }
        self._request("PATCH", self.API_ROOT + "/pages/" + ref, body)

    def ping(self):
        try:
            self._request("GET", self.API_ROOT + "/users/me")
            return True
        except Exception:
            return False

    def _request(self, method, url, body=None):
        if not self.token:
            raise ValueError("missing %s" % self.TOKEN_ENV)
        payload = None
        if body is not None:
            payload = json.dumps(body).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=payload,
            method=method,
            headers={
                "Authorization": "Bearer " + self.token,
                "Notion-Version": self.VERSION,
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request) as response:
                data = response.read().decode("utf-8")
                return json.loads(data) if data else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")
            raise ValueError(
                "Notion API %s %s failed %s: %s" % (method, url, exc.code, detail)
            )
        except urllib.error.URLError as exc:
            raise ValueError("Notion API %s %s failed: %s" % (method, url, exc.reason))

    def _data_source_id(self):
        if not self.data_source_id:
            raise ValueError("missing %s" % self.DATA_SOURCE_ENV)
        return self.data_source_id

    def _task_from_page(self, page):
        properties = page.get("properties", {})
        native_status = self._status_from_property(properties.get(self.STATUS_PROP, {}))
        reverse_status_map = {value: key for key, value in self.status_map.items()}
        status = reverse_status_map.get(native_status)
        if not status:
            raise ValueError("unknown Notion status %r" % native_status)
        return Task(
            ref=page.get("id", ""),
            project=self._text_from_property(properties.get(self.PROJECT_PROP, {})),
            title=self._title_from_property(properties.get(self.NAME_PROP, {})),
            summary=self._text_from_property(properties.get(self.SUMMARY_PROP, {})),
            status=status,
            created=self._created_from_page(page),
        )

    def _created_from_page(self, page):
        created = page.get("created_time")
        prop = page.get("properties", {}).get(self.CREATED_PROP, {})
        if prop.get("created_time"):
            created = prop.get("created_time")
        return created or ""

    def _title_from_property(self, prop):
        return self._plain_text(prop.get("title", []))

    def _text_from_property(self, prop):
        return self._plain_text(prop.get("rich_text", []))

    def _status_from_property(self, prop):
        status = prop.get("status") or prop.get("select") or {}
        return status.get("name", "")

    def _plain_text(self, parts):
        return "".join(part.get("plain_text", "") for part in parts)

    def _title_value(self, value):
        return {"title": [{"type": "text", "text": {"content": value or ""}}]}

    def _text_value(self, value):
        return {"rich_text": [{"type": "text", "text": {"content": value or ""}}]}

    def _status_value(self, value):
        return {self.status_kind: {"name": value}}


PROVIDER = NotionProvider
