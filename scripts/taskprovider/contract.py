from abc import ABC, abstractmethod
from dataclasses import dataclass


CANONICAL_STATUSES = ("backlog", "started", "done", "archived")


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


class TaskProvider(ABC):
    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)
        method = cls.__dict__.get("set_status")
        if method is not None:
            def checked(self, ref, status):
                validate_status(status)
                return method(self, ref, status)
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
    def ping(self):
        raise NotImplementedError

    def add_progress(self, ref, note):
        return None
