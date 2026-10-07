#!/usr/bin/env python3
"""Unit tests for report_digest.py (no network, no database).

    python3 scripts/test_report_digest.py
"""
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import report_digest as rd  # noqa: E402


class ReportDigestTests(unittest.TestCase):
    def row(self, **kw):
        base = {"id": "1", "created_at": "2026-10-07 16:58:12.123456+00", "reason": "Spam",
                "activity_id": "", "reporter": "sam_walks", "target": "jamie_runs",
                "target_id": "t1", "target_total": "1"}
        base.update(kw)
        return base

    def test_parses_psql_timestamps(self):
        self.assertEqual(rd.parse_ts("2026-10-07 16:58:12.123456+00"),
                         datetime(2026, 10, 7, 16, 58, 12, 123456, tzinfo=timezone.utc))
        self.assertEqual(rd.parse_ts("2026-10-07 16:58:12+00").tzinfo, timezone.utc)

    def test_subject_counts_and_pluralises(self):
        self.assertEqual(rd.format_digest([self.row()])[0], "Milepost: 1 new report")
        self.assertEqual(rd.format_digest([self.row(), self.row(id="2")])[0], "Milepost: 2 new reports")

    def test_body_names_both_sides_and_repeat_offenders(self):
        _, body = rd.format_digest([self.row(activity_id="a1", target_total="3")])
        self.assertIn("@jamie_runs reported by @sam_walks: Spam", body)
        self.assertIn("activity a1", body)
        self.assertIn("3 reports against them in total", body)

    def test_deleted_accounts_still_render(self):
        _, body = rd.format_digest([self.row(reporter="", target="")])
        self.assertIn("(deleted user t1) reported by (deleted user)", body)


if __name__ == "__main__":
    unittest.main()
