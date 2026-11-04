"""
Unit tests for the XML attendance exporter script.
"""

import json
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

from scripts.export_attendance_xml import generate_attendance_xml


def test_generate_attendance_xml_structure():
    sample_data = {
        "sessionId": "offline-1730745600000",
        "assignmentId": 42,
        "subject": "Distributed Systems",
        "savedAt": "2026-11-04T15:45:00.000Z",
        "decisions": [
            {
                "student_id": "25CE001",
                "student_name": "Carol Danvers",
                "is_present": True,
                "hits": 18,
                "total": 20,
                "verified": True,
            },
            {
                "student_id": "25CE002",
                "student_name": "Peter Parker",
                "is_present": False,
                "hits": 3,
                "total": 20,
                "verified": False,
            },
        ],
    }

    xml_str = generate_attendance_xml(sample_data)
    assert xml_str.startswith("<?xml")

    root = ET.fromstring(xml_str.encode("utf-8"))
    assert root.tag == "attendanceSession"

    metadata = root.find("metadata")
    assert metadata is not None
    assert metadata.findtext("sessionId") == "offline-1730745600000"
    assert metadata.findtext("subject") == "Distributed Systems"
    assert metadata.findtext("assignmentId") == "42"
    assert metadata.findtext("date") == "2026-11-04"
    assert metadata.findtext("totalStudents") == "2"
    assert metadata.findtext("presentCount") == "1"
    assert metadata.findtext("absentCount") == "1"

    students = root.find("students")
    assert students is not None
    student_list = students.findall("student")
    assert len(student_list) == 2

    s1 = student_list[0]
    assert s1.findtext("id") == "25CE001"
    assert s1.findtext("status") == "Present"
    assert s1.findtext("hits") == "18"
    assert s1.findtext("verified") == "true"

    s2 = student_list[1]
    assert s2.findtext("id") == "25CE002"
    assert s2.findtext("status") == "Absent"
    assert s2.findtext("hits") == "3"
    assert s2.findtext("verified") == "false"


def test_export_attendance_xml_cli(tmp_path):
    json_path = tmp_path / "test_session.json"
    xml_path = tmp_path / "output_folder" / "attendance.xml"

    payload = {
        "sessionId": "local-999",
        "subject": "Algorithm Design",
        "savedAt": "2026-11-04 10:00:00",
        "decisions": [
            {
                "student_id": "STU100",
                "is_present": True,
                "hits": 10,
                "total": 10,
                "verified": True,
            }
        ],
    }
    json_path.write_text(json.dumps(payload), encoding="utf-8")

    result = subprocess.run(
        [
            sys.executable,
            "scripts/export_attendance_xml.py",
            "--input",
            str(json_path),
            "--output",
            str(xml_path),
        ],
        capture_output=True,
        text=True,
        cwd=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")),
    )
    assert result.returncode == 0, f"CLI failed: {result.stderr}"
    assert xml_path.exists()

    content = xml_path.read_text(encoding="utf-8")
    assert "<sessionId>local-999</sessionId>" in content
    assert "<subject>Algorithm Design</subject>" in content
    assert "<status>Present</status>" in content
