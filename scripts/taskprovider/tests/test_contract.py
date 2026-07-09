import inspect
import unittest

from taskprovider.contract import TaskProvider


class ContractTests(unittest.TestCase):
    def test_task_provider_is_abstract(self):
        with self.assertRaises(TypeError):
            TaskProvider()

    def test_subclass_missing_abstract_method_fails(self):
        class Missing(TaskProvider):
            @property
            def status_map(self):
                return {}

            def resolve_project(self, name):
                return name

            def capture(self, project, title, summary):
                return "ref"

            def list(self, project, status):
                return []

            def get(self, ref):
                return None

            def update(self, ref, *, title=None, summary=None):
                return None

            def set_status(self, ref, status):
                return None

        with self.assertRaises(TypeError):
            Missing()

    def test_set_status_rejects_non_canonical_before_dispatch(self):
        class Provider(TaskProvider):
            def __init__(self):
                self.dispatched = False

            @property
            def status_map(self):
                return {}

            def resolve_project(self, name):
                return name

            def capture(self, project, title, summary):
                return "ref"

            def list(self, project, status):
                return []

            def get(self, ref):
                return None

            def update(self, ref, *, title=None, summary=None):
                return None

            def set_status(self, ref, status):
                self.dispatched = True

            def ping(self):
                return True

        provider = Provider()
        with self.assertRaises(ValueError):
            provider.set_status("ref", "blocked")
        self.assertFalse(provider.dispatched)

    def test_update_exposes_only_title_and_summary(self):
        signature = inspect.signature(TaskProvider.update)
        self.assertEqual(["self", "ref", "title", "summary"], list(signature.parameters))
        self.assertEqual(inspect.Parameter.KEYWORD_ONLY, signature.parameters["title"].kind)
        self.assertEqual(inspect.Parameter.KEYWORD_ONLY, signature.parameters["summary"].kind)

    def test_summary_wrappers_preserve_capture_and_update_signatures(self):
        class Provider(TaskProvider):
            @property
            def status_map(self):
                return {}

            def resolve_project(self, name):
                return name

            def capture(self, project, title, summary):
                return "ref"

            def list(self, project, status):
                return []

            def get(self, ref):
                return None

            def update(self, ref, *, title=None, summary=None):
                return None

            def set_status(self, ref, status):
                return None

            def ping(self):
                return True

        capture = inspect.signature(Provider.capture)
        update = inspect.signature(Provider.update)
        self.assertEqual(["self", "project", "title", "summary"], list(capture.parameters))
        self.assertEqual(["self", "ref", "title", "summary"], list(update.parameters))
        self.assertEqual(inspect.Parameter.KEYWORD_ONLY, update.parameters["title"].kind)
        self.assertEqual(inspect.Parameter.KEYWORD_ONLY, update.parameters["summary"].kind)


if __name__ == "__main__":
    unittest.main()
