import os
import unittest

from taskprovider.providers.notion import NotionProvider


class NotionProviderOfflineTests(unittest.TestCase):
    def setUp(self):
        self.saved_env = {
            "NOTION_TOKEN": os.environ.pop("NOTION_TOKEN", None),
            "NOTION_DATA_SOURCE_ID": os.environ.pop("NOTION_DATA_SOURCE_ID", None),
            # Isolate the status-property kind so a shell env (e.g. select) can't
            # leak into these offline tests, which assert the default status shape.
            "NOTION_STATUS_KIND": os.environ.pop("NOTION_STATUS_KIND", None),
        }
        self.provider = NotionProvider()
        self.provider.data_source_id = "data-source-123"
        self.calls = []

        def fake_request(method, url, body=None):
            self.calls.append((method, url, body))
            if method == "POST" and url.endswith("/pages"):
                return {"id": "01234567-89ab-cdef-0123-456789abcdef"}
            if method == "POST" and url.endswith("/data_sources/data-source-123/query"):
                return {"results": [self.page_fixture()]}
            if method == "GET" and url.endswith("/pages/01234567-89ab-cdef-0123-456789abcdef"):
                return self.page_fixture()
            return {}

        self.provider._request = fake_request

    def tearDown(self):
        for key, value in self.saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def page_fixture(self):
        return {
            "id": "01234567-89ab-cdef-0123-456789abcdef",
            "created_time": "2026-06-12T10:11:12.000Z",
            "properties": {
                "Name": {
                    "title": [{"plain_text": "Ship Notion Provider"}],
                },
                "Summary": {
                    "rich_text": [{"plain_text": "fixture summary"}],
                },
                "Project": {
                    "rich_text": [{"plain_text": "alpha"}],
                },
                "Status": {
                    "status": {"name": "Backlog"},
                },
                "Claude": {
                    "checkbox": True,
                },
            },
        }

    def test_capture_builds_page_create_request(self):
        ref = self.provider.capture("alpha", "Ship Notion Provider", "initial summary")

        self.assertEqual("01234567-89ab-cdef-0123-456789abcdef", ref)
        method, url, body = self.calls[-1]
        self.assertEqual("POST", method)
        self.assertTrue(url.endswith("/v1/pages"))
        self.assertEqual("data-source-123", body["parent"]["data_source_id"])
        props = body["properties"]
        self.assertEqual("Ship Notion Provider", props["Name"]["title"][0]["text"]["content"])
        self.assertEqual("initial summary", props["Summary"]["rich_text"][0]["text"]["content"])
        self.assertEqual("alpha", props["Project"]["rich_text"][0]["text"]["content"])
        self.assertEqual("Backlog", props["Status"]["status"]["name"])
        self.assertTrue(props["Claude"]["checkbox"])

    def test_list_builds_query_filter_and_parses_tasks(self):
        tasks = self.provider.list("alpha", "backlog")

        method, url, body = self.calls[-1]
        self.assertEqual("POST", method)
        self.assertTrue(url.endswith("/v1/data_sources/data-source-123/query"))
        filters = body["filter"]["and"]
        self.assertIn({"property": "Claude", "checkbox": {"equals": True}}, filters)
        self.assertIn({"property": "Project", "rich_text": {"equals": "alpha"}}, filters)
        self.assertIn({"property": "Status", "status": {"equals": "Backlog"}}, filters)
        self.assertEqual(1, len(tasks))
        self.assertEqual("01234567-89ab-cdef-0123-456789abcdef", tasks[0].ref)
        self.assertEqual("alpha", tasks[0].project)
        self.assertEqual("Ship Notion Provider", tasks[0].title)
        self.assertEqual("fixture summary", tasks[0].summary)
        self.assertEqual("backlog", tasks[0].status)
        self.assertEqual("2026-06-12T10:11:12.000Z", tasks[0].created)

    def test_update_summary_writes_only_summary_property(self):
        self.provider.update("01234567-89ab-cdef-0123-456789abcdef", summary="updated summary")

        method, url, body = self.calls[-1]
        self.assertEqual("PATCH", method)
        self.assertTrue(url.endswith("/v1/pages/01234567-89ab-cdef-0123-456789abcdef"))
        self.assertEqual(["Summary"], list(body["properties"].keys()))
        self.assertEqual("updated summary", body["properties"]["Summary"]["rich_text"][0]["text"]["content"])

    def test_page_response_parses_every_task_field(self):
        task = self.provider.get("01234567-89ab-cdef-0123-456789abcdef")

        self.assertEqual("01234567-89ab-cdef-0123-456789abcdef", task.ref)
        self.assertEqual("alpha", task.project)
        self.assertEqual("Ship Notion Provider", task.title)
        self.assertEqual("fixture summary", task.summary)
        self.assertEqual("backlog", task.status)
        self.assertEqual("2026-06-12T10:11:12.000Z", task.created)

    def test_status_map_round_trips(self):
        reverse = {value: key for key, value in self.provider.status_map.items()}
        for canonical, native in self.provider.status_map.items():
            self.assertEqual(canonical, reverse[native])

    def test_ref_methods_reject_short_ids(self):
        # A short prefix is ambiguous + rejected by the API — guard fails early
        # with an actionable message, before any request goes out.
        for op in (
            lambda: self.provider.get("38ef6850"),
            lambda: self.provider.set_status("38ef6850", "done"),
            lambda: self.provider.update("38ef6850", summary="x"),
        ):
            before = len(self.calls)
            with self.assertRaises(ValueError) as ctx:
                op()
            self.assertIn("full page UUID", str(ctx.exception))
            self.assertEqual(before, len(self.calls), "guard must not hit the API")

    def test_ref_methods_accept_full_uuid_dashed_or_not(self):
        # Both the dashed fixture id and its dashless form pass the guard.
        self.provider.get("01234567-89ab-cdef-0123-456789abcdef")
        self.provider.update("0123456789abcdef0123456789abcdef", summary="ok")
        method, url, _ = self.calls[-1]
        self.assertEqual("PATCH", method)


@unittest.skipUnless(
    os.environ.get("NOTION_TOKEN") and os.environ.get("NOTION_TEST_DATA_SOURCE_ID"),
    "live Notion creds not set",
)
class NotionProviderLiveTests(unittest.TestCase):
    def setUp(self):
        os.environ["NOTION_DATA_SOURCE_ID"] = os.environ["NOTION_TEST_DATA_SOURCE_ID"]
        self.provider = NotionProvider()
        self.project = "codex-live-smoke"

    def test_lifecycle(self):
        ref = self.provider.capture(self.project, "Live Notion Provider", "initial summary")
        self.addCleanup(lambda: self._archive_if_possible(ref))

        self.assertIn(ref, [task.ref for task in self.provider.list(self.project, "backlog")])

        self.provider.update(ref, summary="updated summary")
        task = self.provider.get(ref)
        self.assertEqual("updated summary", task.summary)
        self.assertEqual("backlog", task.status)

        self.provider.set_status(ref, "started")
        self.assertNotIn(ref, [task.ref for task in self.provider.list(self.project, "backlog")])
        self.assertIn(ref, [task.ref for task in self.provider.list(self.project, "started")])

        self.provider.set_status(ref, "done")
        task = self.provider.get(ref)
        self.assertEqual("done", task.status)

        self.provider.set_status(ref, "archived")
        task = self.provider.get(ref)
        self.assertEqual("archived", task.status)

    def _archive_if_possible(self, ref):
        try:
            if self.provider.get(ref).status != "archived":
                self.provider.set_status(ref, "archived")
        except Exception:
            pass


if __name__ == "__main__":
    unittest.main()
