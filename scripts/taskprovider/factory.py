import importlib
import os


def get_provider():
    # Generic registry: the env value IS the provider module name under
    # taskprovider.providers.* exposing a PROVIDER class. Adding a backend is a
    # drop-in module — the factory never names a specific backend, so it stays
    # boundary-neutral and needs no edit per new provider.
    selected = os.environ.get("MEMORY_TASK_PROVIDER", "local")
    try:
        module = importlib.import_module("taskprovider.providers." + selected)
    except ImportError:
        raise ValueError("unknown task provider %r" % selected)
    cls = getattr(module, "PROVIDER", None)
    if cls is None:
        raise ValueError("provider module %r exposes no PROVIDER class" % selected)
    return cls()
