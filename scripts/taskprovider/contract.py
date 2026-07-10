from abc import ABC, abstractmethod
from dataclasses import dataclass


CANONICAL_STATUSES = ("backlog", "started", "done", "archived")
SUMMARY_MAX_CHARS = 500


@dataclass(frozen=True)
class Task:
    ref: str
    project: str
    title: str
    summary: str
    status: str
    created: str


def validate_status(status):
    if status not in CANONICAL_STATUSES:
        allowed = ", ".join(CANONICAL_STATUSES)
        raise ValueError("invalid status %r; expected one of: %s" % (status, allowed))
    return status


def validate_summary(summary):
    length = len(summary)
    if length > SUMMARY_MAX_CHARS:
        raise ValueError(
            "summary is %d chars; maximum is %d. Write the long form to an investigation "
            "in the task's project (projects/<project>/investigations/<slug>.md), then "
            "reference it from the summary by name — <slug>, not a path: paths move "
            "when work is archived, and the task already carries its project."
            % (length, SUMMARY_MAX_CHARS)
        )
    return summary


class TaskProvider(ABC):
    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)
        method = cls.__dict__.get("capture")
        if method is not None:
            def make_checked_capture(wrapped):
                def checked_capture(self, project, title, summary):
                    validate_summary(summary)
                    return wrapped(self, project, title, summary)
                return checked_capture
            checked_capture = make_checked_capture(method)
            checked_capture.__name__ = method.__name__
            checked_capture.__doc__ = method.__doc__
            checked_capture.__isabstractmethod__ = getattr(method, "__isabstractmethod__", False)
            setattr(cls, "capture", checked_capture)
        method = cls.__dict__.get("update")
        if method is not None:
            def make_checked_update(wrapped):
                def checked_update(self, ref, *, title=None, summary=None):
                    if summary is not None:
                        validate_summary(summary)
                    return wrapped(self, ref, title=title, summary=summary)
                return checked_update
            checked_update = make_checked_update(method)
            checked_update.__name__ = method.__name__
            checked_update.__doc__ = method.__doc__
            checked_update.__isabstractmethod__ = getattr(method, "__isabstractmethod__", False)
            setattr(cls, "update", checked_update)
        method = cls.__dict__.get("set_status")
        if method is not None:
            def make_checked_status(wrapped):
                def checked(self, ref, status):
                    validate_status(status)
                    return wrapped(self, ref, status)
                return checked
            checked = make_checked_status(method)
            checked.__name__ = method.__name__
            checked.__doc__ = method.__doc__
            checked.__isabstractmethod__ = getattr(method, "__isabstractmethod__", False)
            setattr(cls, "set_status", checked)

    @property
    @abstractmethod
    def status_map(self):
        raise NotImplementedError

    @abstractmethod
    def resolve_project(self, name):
        raise NotImplementedError

    @abstractmethod
    def capture(self, project, title, summary):
        raise NotImplementedError

    @abstractmethod
    def list(self, project, status):
        raise NotImplementedError

    @abstractmethod
    def get(self, ref):
        raise NotImplementedError

    @abstractmethod
    def update(self, ref, *, title=None, summary=None):
        raise NotImplementedError

    @abstractmethod
    def set_status(self, ref, status):
        raise NotImplementedError

    @abstractmethod
    def delete(self, ref):
        raise NotImplementedError

    @abstractmethod
    def ping(self):
        raise NotImplementedError

    def add_progress(self, ref, note):
        return None
