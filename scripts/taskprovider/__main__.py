import argparse
import json
import sys
from dataclasses import asdict

from taskprovider.contract import validate_status
from taskprovider.factory import get_provider


def emit(payload, code=0):
    print(json.dumps(payload, sort_keys=True))
    return code


def task_payload(task):
    return asdict(task)


def run(argv):
    parser = argparse.ArgumentParser(prog="taskprovider")
    sub = parser.add_subparsers(dest="verb")

    p = sub.add_parser("capture")
    p.add_argument("project")
    p.add_argument("title")
    p.add_argument("summary")

    p = sub.add_parser("list")
    p.add_argument("project")
    p.add_argument("status")

    p = sub.add_parser("get")
    p.add_argument("ref")

    p = sub.add_parser("update")
    p.add_argument("ref")
    p.add_argument("--title")
    p.add_argument("--summary")

    p = sub.add_parser("set-status")
    p.add_argument("ref")
    p.add_argument("status")

    p = sub.add_parser("delete")
    p.add_argument("ref")

    sub.add_parser("ping")

    try:
        args = parser.parse_args(argv)
        if args.verb is None:
            raise ValueError("unknown verb")
        if args.verb in ("list", "set-status"):
            validate_status(args.status)
        provider = get_provider()
        if args.verb == "capture":
            ref = provider.capture(args.project, args.title, args.summary)
            return emit({"ref": ref})
        if args.verb == "list":
            return emit({"tasks": [task_payload(t) for t in provider.list(args.project, args.status)]})
        if args.verb == "get":
            return emit({"task": task_payload(provider.get(args.ref))})
        if args.verb == "update":
            provider.update(args.ref, title=args.title, summary=args.summary)
            return emit({"ok": True})
        if args.verb == "set-status":
            provider.set_status(args.ref, args.status)
            return emit({"ok": True})
        if args.verb == "delete":
            provider.delete(args.ref)
            return emit({"ok": True})
        if args.verb == "ping":
            return emit({"ok": bool(provider.ping())})
        raise ValueError("unknown verb")
    except SystemExit as exc:
        return emit({"error": "invalid arguments"}, exc.code if isinstance(exc.code, int) else 2)
    except Exception as exc:
        return emit({"error": str(exc)}, 1)


def main():
    sys.exit(run(sys.argv[1:]))


if __name__ == "__main__":
    main()
