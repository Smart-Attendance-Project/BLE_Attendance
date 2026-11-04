#!/usr/bin/env python3
"""
Export attendance session data to formatted XML.

Can be run standalone:
    python scripts/export_attendance_xml.py --input <path_to_json> --output <path_to_xml>
Or imported:
    from scripts.export_attendance_xml import generate_attendance_xml
"""

import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET
from xml.dom import minidom


def generate_attendance_xml(data: dict) -> str:
    """Generates formatted XML string from attendance session dictionary."""
    root = ET.Element("attendanceSession")

    metadata = ET.SubElement(root, "metadata")
    ET.SubElement(metadata, "sessionId").text = str(data.get("sessionId", ""))
    ET.SubElement(metadata, "subject").text = str(data.get("subject", "Lecture"))
    if "assignmentId" in data and data["assignmentId"] is not None:
        ET.SubElement(metadata, "assignmentId").text = str(data["assignmentId"])

    saved_at = str(data.get("savedAt", ""))
    date_str = ""
    time_str = ""
    if "T" in saved_at:
        parts = saved_at.split("T")
        date_str = parts[0]
        time_str = parts[1].split(".")[0]
    elif " " in saved_at:
        parts = saved_at.split(" ")
        date_str = parts[0]
        time_str = parts[1].split(".")[0]
    else:
        date_str = saved_at

    ET.SubElement(metadata, "date").text = date_str
    ET.SubElement(metadata, "time").text = time_str
    ET.SubElement(metadata, "savedAt").text = saved_at

    raw_decisions = data.get("decisions", [])
    decisions = raw_decisions if isinstance(raw_decisions, list) else []

    present_count = sum(1 for d in decisions if d.get("is_present") is True)
    absent_count = len(decisions) - present_count

    ET.SubElement(metadata, "totalStudents").text = str(len(decisions))
    ET.SubElement(metadata, "presentCount").text = str(present_count)
    ET.SubElement(metadata, "absentCount").text = str(absent_count)

    students_elem = ET.SubElement(root, "students")
    for d in decisions:
        s = ET.SubElement(students_elem, "student")
        ET.SubElement(s, "id").text = str(d.get("student_id") or d.get("id") or "UNKNOWN")
        if d.get("student_name") or d.get("name"):
            ET.SubElement(s, "name").text = str(d.get("student_name") or d.get("name"))
        is_present = d.get("is_present") is True
        ET.SubElement(s, "status").text = "Present" if is_present else "Absent"
        ET.SubElement(s, "hits").text = str(d.get("hits", 0))
        ET.SubElement(s, "totalHits").text = str(d.get("total", 0))
        ET.SubElement(s, "verified").text = "true" if d.get("verified") is True else "false"

    xml_bytes = ET.tostring(root, encoding="utf-8")
    parsed = minidom.parseString(xml_bytes)
    return parsed.toprettyxml(indent="  ", encoding="utf-8").decode("utf-8")


def main():
    parser = argparse.ArgumentParser(description="Export attendance session data to XML")
    parser.add_argument("--input", "-i", required=True, help="Path to input JSON file containing attendance session data")
    parser.add_argument("--output", "-o", required=True, help="Path to write output XML file")
    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"Error: Input file {args.input} does not exist", file=sys.stderr)
        sys.exit(1)

    with open(args.input, "r", encoding="utf-8") as f:
        data = json.load(f)

    xml_content = generate_attendance_xml(data)

    out_dir = os.path.dirname(os.path.abspath(args.output))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(xml_content)

    print(f"Exported XML successfully to {args.output}")


if __name__ == "__main__":
    main()
