package main

import (
	"fmt"
	"math"
	"strconv"
	"time"
)

const attendanceFields = "session_id,student_user_id,presence_ratio,is_present,biometric_verified"

func enrolled(r *request, session object, student any) bool {
	if session["division_id"] == nil {
		return false
	}
	return r.one(`SELECT id FROM division_students
		WHERE student_user_id=$1 AND division_id=$2 AND ($3::integer IS NULL OR batch_id=$3)`,
		student, session["division_id"], session["batch_id"]) != nil
}

func detection(r *request) any {
	body, student := r.args(), r.user["id"]
	session := r.one(sessionSelect+" WHERE s.id=$1 AND s.is_active", body["session_id"])
	if session == nil {
		fail(404, "Active session not found")
	}
	if !enrolled(r, session, student) {
		fail(403, "Student is not enrolled in this class")
	}
	r.exec(`INSERT INTO detections (session_id,student_user_id,rssi,proximity_ok,detected_at) VALUES ($1,$2,$3,$4,$5)`,
		session["id"], student, body["rssi"], body["proximity_ok"], nowUTC())
	return message("Detection recorded")
}

func detectionBatch(r *request) any {
	recorded := r.exec(`INSERT INTO detections (session_id,student_user_id,rssi,proximity_ok,detected_at)
		SELECT s.id,u.id,detection.rssi,detection.proximity_ok,clock_timestamp() AT TIME ZONE 'UTC'
		FROM jsonb_to_recordset($1) AS detection(session_id text,student_identifier text,rssi integer,proximity_ok boolean)
		JOIN sessions s ON s.id=detection.session_id AND s.is_active AND s.teacher_user_id=$2
		JOIN teacher_assignments a ON a.id=s.assignment_id JOIN divisions d ON d.id=a.division_id
		JOIN users u ON u.student_id=detection.student_identifier
		JOIN division_students e ON e.student_user_id=u.id AND e.division_id=a.division_id
			AND (a.batch_id IS NULL OR e.batch_id=a.batch_id)
		WHERE (COALESCE(d.start_student_id,'')='' OR detection.student_identifier COLLATE "C" >= d.start_student_id)
		  AND (COALESCE(d.end_student_id,'')='' OR detection.student_identifier COLLATE "C" <= d.end_student_id)`,
		r.args()["detections"], r.user["id"])
	return message(fmt.Sprintf("%d detections recorded", recorded))
}

func ratio(detections int64, start, end time.Time) float64 {
	windows := max(1, math.Floor(end.Sub(start).Seconds()/30))
	result := float64(detections) / windows
	// Python rounds the stored binary float directly to three places.
	// Fixed decimal formatting avoids a second rounding at the scaled value.
	rounded, _ := strconv.ParseFloat(strconv.FormatFloat(result, 'f', 3, 64), 64)
	return min(1, rounded)
}

func finalizeAttendance(r *request) any {
	body, student := r.args(), r.user["id"]
	return r.transaction(func() any {
		session := requireSession(r, body["session_id"], nil, sessionReadLock)
		if !enrolled(r, session, student) {
			fail(403, "Student is not enrolled in this class")
		}
		if !flag(session["finalization_open"]) {
			fail(409, "Finalization not open")
		}
		now := nowUTC()
		count := r.one("SELECT count(*) AS detections FROM detections WHERE session_id=$1 AND student_user_id=$2 AND proximity_ok",
			session["id"], student)["detections"].(int64)
		presence := ratio(count, session["starts_at"].(time.Time), now)
		verified := flag(body["biometric_verified"])
		var finalized any
		if verified {
			finalized = now
		}
		return r.one(`INSERT INTO attendance (session_id,student_user_id,presence_ratio,is_present,biometric_verified,overridden_by_teacher,finalized_at)
			VALUES ($1,$2,$3,$4,$5,false,$6) ON CONFLICT (session_id,student_user_id) DO UPDATE SET
			presence_ratio=CASE WHEN EXCLUDED.presence_ratio > 0 THEN EXCLUDED.presence_ratio ELSE attendance.presence_ratio END,
			biometric_verified=EXCLUDED.biometric_verified,
			is_present=EXCLUDED.biometric_verified AND
				(CASE WHEN EXCLUDED.presence_ratio > 0 THEN EXCLUDED.presence_ratio ELSE attendance.presence_ratio END) >= 0.75,
			finalized_at=COALESCE(EXCLUDED.finalized_at,attendance.finalized_at) RETURNING `+attendanceFields,
			session["id"], student, presence, presence >= 0.75 && verified, verified, finalized)
	})
}

func protectedSession(r *request, lock sessionLock) object {
	var owner any = r.user["id"]
	if r.user["role"] == "admin" {
		owner = nil
	}
	return requireSession(r, r.path["session_id"], owner, lock)
}

func overrideAttendance(r *request) any {
	return r.transaction(func() any {
		session := protectedSession(r, sessionWriteLock)
		if flag(session["attendance_locked"]) {
			fail(409, "Attendance is locked")
		}
		body := r.args()
		student := body["student_user_id"]
		if r.one("SELECT id FROM users WHERE id=$1 AND role='student'", student) == nil {
			fail(404, "Student not found")
		}
		if !enrolled(r, session, student) {
			fail(403, "Student is not enrolled in this class")
		}
		return r.one(`INSERT INTO attendance
			(session_id,student_user_id,presence_ratio,is_present,biometric_verified,overridden_by_teacher,override_reason)
			VALUES ($1,$2,0,$3,false,true,$4) ON CONFLICT (session_id,student_user_id) DO UPDATE
			SET is_present=EXCLUDED.is_present,overridden_by_teacher=true,override_reason=EXCLUDED.override_reason
			RETURNING `+attendanceFields, session["id"], student, body["is_present"], body["reason"])
	})
}

func batchAttendance(r *request) any {
	return r.transaction(func() any {
		session := protectedSession(r, sessionWriteLock)
		if flag(session["attendance_locked"]) {
			fail(409, "Attendance is locked")
		}
		items := []object{}
		for _, entry := range r.body.([]any) {
			item := entry.(object)
			if id, ok := item["student_id"].(string); ok {
				items = append(items, object{"student_id": id, "is_present": truth(item["is_present"])})
			}
		}
		if len(items) == 0 {
			return message("0 attendance records saved")
		}
		rows := r.one(`WITH eligible AS (
			SELECT u.id,input.is_present,input.position
			FROM ROWS FROM (
				jsonb_to_recordset($1) AS (student_id text,is_present boolean)
			) WITH ORDINALITY AS input(student_id,is_present,position)
			JOIN users u ON u.student_id=input.student_id
			WHERE $3::integer IS NULL OR EXISTS (
				SELECT 1 FROM division_students e WHERE e.student_user_id=u.id AND e.division_id=$3
					AND ($4::integer IS NULL OR e.batch_id=$4)
			)
		), latest AS (
			SELECT DISTINCT ON (id) id,is_present FROM eligible ORDER BY id,position DESC
		), updates AS (
			INSERT INTO attendance (session_id,student_user_id,presence_ratio,is_present,biometric_verified,overridden_by_teacher,override_reason)
			SELECT $2,id,CASE WHEN is_present THEN 1 ELSE 0 END,is_present,false,true,'BLE batch submit' FROM latest
			ON CONFLICT (session_id,student_user_id) DO UPDATE SET presence_ratio=EXCLUDED.presence_ratio,
				is_present=EXCLUDED.is_present,overridden_by_teacher=true,override_reason=EXCLUDED.override_reason
		) SELECT count(*) AS updated FROM eligible`, items, session["id"], session["division_id"], session["batch_id"])
		return message(fmt.Sprintf("%d attendance records saved", rows["updated"]))
	})
}

func lockAttendance(r *request) any {
	if r.exec("UPDATE sessions SET attendance_locked=true WHERE id=$1 AND teacher_user_id=$2", r.path["session_id"], r.user["id"]) == 0 {
		fail(404, "Session not found")
	}
	return message("Attendance locked")
}

func sessionDetections(r *request) any {
	session := protectedSession(r, sessionNoLock)
	rows := r.all(`SELECT u.student_id,u.full_name AS student_name,d.rssi,d.proximity_ok,d.detected_at
		FROM detections d JOIN users u ON u.id=d.student_user_id WHERE d.session_id=$1 ORDER BY d.detected_at DESC`, session["id"])
	for _, row := range rows {
		row["detected_at"] = isoTimestamp(row["detected_at"])
	}
	return rows
}

func attendanceSummary(r *request) any {
	session := protectedSession(r, sessionNoLock)
	rows := r.all(`WITH detections_in_session AS (
		SELECT student_user_id,count(*) AS detection_count,count(*) FILTER (WHERE proximity_ok) AS valid_count
		FROM detections WHERE session_id=$1 GROUP BY student_user_id
	), students AS (
		SELECT student_user_id FROM division_students
		WHERE division_id=$2::integer AND ($3::integer IS NULL OR batch_id=$3)
		UNION ALL
		SELECT student_user_id FROM detections_in_session WHERE $2::integer IS NULL
	)
	SELECT u.id AS student_user_id,u.student_id,u.full_name AS student_name,
		COALESCE(d.detection_count,0) AS detection_count,COALESCE(d.valid_count,0) AS valid_count,
		a.presence_ratio,COALESCE(a.is_present,false) AS is_present,COALESCE(a.biometric_verified,false) AS biometric_verified,
		COALESCE(a.overridden_by_teacher,false) AS overridden_by_teacher,a.override_reason
	FROM students s JOIN users u ON u.id=s.student_user_id
	LEFT JOIN detections_in_session d ON d.student_user_id=u.id
	LEFT JOIN attendance a ON a.session_id=$1 AND a.student_user_id=u.id ORDER BY u.student_id`,
		session["id"], session["division_id"], session["batch_id"])
	end, ok := session["ends_at"].(time.Time)
	if !ok {
		end = nowUTC()
	}
	start := session["starts_at"].(time.Time)
	present := 0
	for _, row := range rows {
		if !flag(row["overridden_by_teacher"]) {
			presence := ratio(row["valid_count"].(int64), start, end)
			row["presence_ratio"] = presence
			row["is_present"] = presence >= 0.75 && flag(row["biometric_verified"])
		}
		delete(row, "valid_count")
		if flag(row["is_present"]) {
			present++
		}
	}
	return object{"session_id": session["id"], "subject": session["subject"], "starts_at": isoTimestamp(start),
		"ends_at": isoTimestamp(session["ends_at"]), "total_students": len(rows), "present_students": present, "records": rows}
}
