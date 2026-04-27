#!/usr/bin/env python3
import datetime as dt
import json
import os
import sqlite3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


DB_FILE = os.environ.get("KUMA_DB_FILE", "/data/kuma.db")
STALE_SECONDS = int(os.environ.get("STATUS_STALE_SECONDS", "300"))


def utc_now():
    return dt.datetime.now(dt.timezone.utc)


def parse_kuma_time(value):
    if not value:
        return None
    normalized = value.replace("Z", "+00:00")
    parsed = dt.datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def latest_status(name):
    # Use normal read-only mode so SQLite can see Uptime Kuma's latest WAL
    # entries. immutable=1 can miss fresh heartbeat rows and mark healthy
    # monitors as stale.
    with sqlite3.connect(f"file:{DB_FILE}?mode=ro", uri=True) as conn:
        conn.row_factory = sqlite3.Row
        row = conn.execute(
            """
            select
              m.id,
              m.name,
              h.status,
              h.msg,
              h.time
            from monitor m
            left join heartbeat h on h.id = (
              select h2.id
              from heartbeat h2
              where h2.monitor_id = m.id
              order by h2.time desc
              limit 1
            )
            where m.name = ?
            """,
            (name,),
        ).fetchone()

    if row is None:
        return 404, {
            "ok": False,
            "name": name,
            "reason": "monitor_not_found",
            "message": "Uptime Kuma monitor was not found.",
        }

    heartbeat_time = parse_kuma_time(row["time"])
    age_seconds = None
    if heartbeat_time is not None:
        age_seconds = int((utc_now() - heartbeat_time).total_seconds())

    if row["status"] != 1:
        return 503, {
            "ok": False,
            "name": row["name"],
            "status": row["status"],
            "message": row["msg"] or "Monitor is down.",
            "time": row["time"],
            "age_seconds": age_seconds,
        }

    if age_seconds is None or age_seconds > STALE_SECONDS:
        return 503, {
            "ok": False,
            "name": row["name"],
            "status": row["status"],
            "message": "Monitor heartbeat is stale.",
            "time": row["time"],
            "age_seconds": age_seconds,
        }

    return 200, {
        "ok": True,
        "name": row["name"],
        "status": row["status"],
        "message": row["msg"] or "Up",
        "time": row["time"],
        "age_seconds": age_seconds,
    }


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self.send_json(200, {"ok": True})
            return

        if parsed.path != "/status":
            self.send_json(404, {"ok": False, "message": "Not found"})
            return

        name = parse_qs(parsed.query).get("name", [""])[0]
        if not name:
            self.send_json(400, {"ok": False, "message": "Missing name query"})
            return

        try:
            code, payload = latest_status(name)
        except Exception as exc:
            code, payload = 500, {"ok": False, "message": str(exc)}

        self.send_json(code, payload)

    def do_HEAD(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self.send_response(200)
            self.end_headers()
            return

        if parsed.path != "/status":
            self.send_response(404)
            self.end_headers()
            return

        name = parse_qs(parsed.query).get("name", [""])[0]
        if not name:
            self.send_response(400)
            self.end_headers()
            return

        try:
            code, _ = latest_status(name)
        except Exception:
            code = 500
        self.send_response(code)
        self.end_headers()

    def send_json(self, code, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, _format, *_args):
        return


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    server.serve_forever()
