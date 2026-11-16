package main

import (
	"fmt"
	"time"

	"github.com/xuri/excelize/v2"
)

func exportAttendance(r *request) any {
	assignment := r.one(`SELECT a.id,a.division_id,a.batch_id,s.code FROM teacher_assignments a
		JOIN subjects s ON s.id=a.subject_id WHERE a.id=$1 AND a.teacher_user_id=$2`,
		r.query["assignment_id"], r.user["id"])
	if assignment == nil {
		fail(404, "Assignment not found")
	}
	from, to := textValue(r.query["from_date"]), textValue(r.query["to_date"])
	start, end := parseDateTime(from), parseDateTime(to+"T23:59:59")
	sessions := r.all(`SELECT id,starts_at FROM sessions
		WHERE assignment_id=$1 AND starts_at BETWEEN $2 AND $3 AND NOT is_active ORDER BY starts_at`, assignment["id"], start, end)
	students := r.all(`SELECT u.id,u.student_id FROM division_students e JOIN users u ON u.id=e.student_user_id
		WHERE e.division_id=$1 AND ($2::integer IS NULL OR e.batch_id=$2) ORDER BY u.student_id`, assignment["division_id"], assignment["batch_id"])
	sessionIDs := make([]string, 0, len(sessions))
	for _, session := range sessions {
		sessionIDs = append(sessionIDs, textValue(session["id"]))
	}
	type attendanceKey struct{ sessionID, studentID string }
	present := map[attendanceKey]bool{}
	if len(sessionIDs) != 0 {
		for _, row := range r.all(`SELECT session_id,student_user_id,is_present FROM attendance WHERE session_id=ANY($1)`, sessionIDs) {
			present[attendanceKey{textValue(row["session_id"]), textValue(row["student_user_id"])}] = flag(row["is_present"])
		}
	}
	workbook := excelize.NewFile()
	defer workbook.Close()
	const sheet = "Attendance"
	check(workbook.SetSheetName("Sheet1", sheet))
	lastCell, err := excelize.CoordinatesToCellName(len(sessions)+1, len(students)+1)
	check(err)
	check(workbook.SetSheetDimension(sheet, "A1:"+lastCell))
	writer, err := workbook.NewStreamWriter(sheet)
	check(err)
	header := []any{"ID"}
	for _, session := range sessions {
		header = append(header, session["starts_at"].(time.Time).Format("02/01/2006"))
	}
	check(writer.SetRow("A1", header))
	for i, student := range students {
		studentID := textValue(student["id"])
		cells := []any{student["student_id"]}
		for _, sessionID := range sessionIDs {
			cell := "A"
			if present[attendanceKey{sessionID, studentID}] {
				cell = "P"
			}
			cells = append(cells, cell)
		}
		check(writer.SetRow(fmt.Sprintf("A%d", i+2), cells))
	}
	check(writer.Flush())
	data, err := workbook.WriteToBuffer()
	check(err)
	return download{
		data: data.Bytes(), contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
		filename: fmt.Sprintf("attendance_%s_%s_to_%s.xlsx", assignment["code"], from, to),
	}
}
