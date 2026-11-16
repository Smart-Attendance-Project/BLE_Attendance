package main

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"time"

	"github.com/google/uuid"
)

const sessionSelect = `SELECT s.id,s.subject,p.code AS subject_code,s.token,s.teacher_user_id,s.assignment_id,
	s.starts_at,s.ends_at,s.is_active,s.finalization_open,COALESCE(s.attendance_locked,false) AS attendance_locked,
	d.start_student_id,d.end_student_id,a.division_id,a.batch_id
	FROM sessions s LEFT JOIN teacher_assignments a ON a.id=s.assignment_id
	LEFT JOIN divisions d ON d.id=a.division_id LEFT JOIN subjects p ON p.id=a.subject_id`

func nowUTC() time.Time {
	return time.Now().UTC().Truncate(time.Microsecond)
}

func isoTimestamp(value any) any {
	at, ok := value.(time.Time)
	if !ok {
		return nil
	}
	if at.Nanosecond() == 0 {
		return at.Format("2006-01-02T15:04:05")
	}
	return at.Format("2006-01-02T15:04:05.000000")
}

func sessionOutput(row object) object {
	row["starts_at"] = isoTimestamp(row["starts_at"])
	row["ends_at"] = isoTimestamp(row["ends_at"])
	return row
}

type sessionLock string

const (
	sessionNoLock    sessionLock = ""
	sessionReadLock  sessionLock = " FOR SHARE OF s"
	sessionWriteLock sessionLock = " FOR UPDATE OF s"
)

func requireSession(r *request, id any, owner any, lock sessionLock) object {
	filters := conditions{}
	filters.add("s.id", "=", id)
	filters.add("s.teacher_user_id", "=", owner)
	query := sessionSelect + filters.where() + string(lock)
	session := r.one(query, filters.args...)
	if session == nil {
		fail(404, "Session not found")
	}
	return session
}

func startSession(r *request) any {
	body := r.args()
	assignmentID := body["assignment_id"]
	if assignmentID == nil {
		fail(422, "A class assignment is required")
	}
	return r.transaction(func() any {
		teacher := r.user["id"]
		// Serialize starts from two devices using the same teacher account.
		r.one("SELECT id FROM users WHERE id=$1 FOR UPDATE", teacher)
		assignment := r.one("SELECT id FROM teacher_assignments WHERE id=$1 AND teacher_user_id=$2", assignmentID, teacher)
		if assignment == nil {
			fail(404, "Assignment not found")
		}
		if r.one("SELECT id FROM sessions WHERE teacher_user_id=$1 AND is_active LIMIT 1", teacher) != nil {
			fail(409, "A session is already active")
		}
		id := uuid.NewString()
		token := make([]byte, 8)
		_, err := rand.Read(token)
		check(err)
		r.exec(`INSERT INTO sessions (id,subject,teacher_user_id,assignment_id,token,starts_at,is_active,finalization_open,attendance_locked)
			VALUES ($1,$2,$3,$4,$5,$6,true,false,false)`, id, body["subject"], teacher, assignmentID, hex.EncodeToString(token), nowUTC())
		return sessionOutput(requireSession(r, id, nil, sessionNoLock))
	})
}

func endSession(r *request) any {
	return r.transaction(func() any {
		id := r.path["session_id"]
		if r.exec("UPDATE sessions SET is_active=false,finalization_open=false,ends_at=$3 WHERE id=$1 AND teacher_user_id=$2", id, r.user["id"], nowUTC()) == 0 {
			fail(404, "Session not found")
		}
		return sessionOutput(requireSession(r, id, nil, sessionNoLock))
	})
}

func activeSession(r *request) any {
	where := " WHERE s.is_active AND "
	switch r.user["role"] {
	case "teacher":
		where += "s.teacher_user_id=$1"
	case "student":
		where += `EXISTS (SELECT 1 FROM division_students e WHERE e.student_user_id=$1 AND e.division_id=a.division_id
			AND (a.batch_id IS NULL OR e.batch_id=a.batch_id))`
	default:
		fail(403, "Unsupported role")
	}
	row := r.one(sessionSelect+where+" ORDER BY s.starts_at DESC LIMIT 1", r.user["id"])
	if row == nil {
		fail(404, "No active session")
	}
	return sessionOutput(row)
}

func openFinalization(r *request) any {
	return r.transaction(func() any {
		id := r.path["session_id"]
		row := requireSession(r, id, r.user["id"], sessionWriteLock)
		if !flag(row["is_active"]) {
			fail(409, "Session already ended")
		}
		r.exec("UPDATE sessions SET finalization_open=true WHERE id=$1", id)
		row["finalization_open"] = true
		return sessionOutput(row)
	})
}

func teacherSessions(r *request) any {
	filter := conditions{}
	filter.add("s.teacher_user_id", "=", r.user["id"])
	filter.add("s.assignment_id", "=", r.query["assignment_id"])
	if value := r.query["from_date"]; value != nil {
		filter.add("s.starts_at", ">=", parseDateTime(textValue(value)))
	}
	if value := r.query["to_date"]; value != nil {
		filter.add("s.starts_at", "<=", parseDateTime(textValue(value)+"T23:59:59"))
	}
	rows := r.all(sessionSelect+filter.where()+" ORDER BY s.starts_at DESC", filter.args...)
	for _, row := range rows {
		sessionOutput(row)
	}
	return rows
}

func parseDateTime(value string) time.Time {
	for _, layout := range []string{
		time.DateOnly, "20060102", "2006-01-02T15:04:05", "2006-01-02 15:04:05",
		"2006-01-02T15:04", "2006-01-02 15:04", time.RFC3339,
	} {
		if at, err := time.Parse(layout, value); err == nil {
			return at
		}
	}
	panic(errors.New("invalid date"))
}

func teacherSchedule(r *request) any {
	return r.all(slotSelect+` WHERE a.teacher_user_id=$1 AND l.day_of_week=$2
		AND l.semester_id=(SELECT id FROM semesters WHERE is_active LIMIT 1) ORDER BY l.time_start`,
		r.user["id"], todayIST())
}

func teacherMobileSchedule(r *request) any {
	return r.all(`SELECT l.id AS slot_id,l.assignment_id,COALESCE(s.name,'') AS subject_name,
		COALESCE(s.code,'') AS subject_code,a.division_id,a.batch_id,COALESCE(d.label,'') AS division_label,
		b.label AS batch_label,l.time_start,l.time_end,l.room,COALESCE(s.subject_type,'lecture') AS subject_type,
		d.start_student_id,d.end_student_id
		FROM schedule_slots l JOIN teacher_assignments a ON a.id=l.assignment_id LEFT JOIN subjects s ON s.id=a.subject_id
		LEFT JOIN divisions d ON d.id=a.division_id LEFT JOIN batches b ON b.id=a.batch_id
		WHERE a.teacher_user_id=$1 AND l.day_of_week=$2
		AND l.semester_id=(SELECT id FROM semesters WHERE is_active LIMIT 1) ORDER BY l.time_start`,
		r.user["id"], todayIST())
}

func todayIST() int {
	return (int(time.Now().In(ist).Weekday()) + 6) % 7
}

func teacherDivisions(r *request) any {
	return r.all(divisionSelect+` WHERE EXISTS (
		SELECT 1 FROM teacher_assignments a WHERE a.division_id=d.id AND a.teacher_user_id=$1)`, r.user["id"])
}

func divisionStudents(r *request) any {
	division := r.path["division_id"]
	if r.one("SELECT id FROM teacher_assignments WHERE teacher_user_id=$1 AND division_id=$2 LIMIT 1", r.user["id"], division) == nil {
		fail(403, "No assignment in this division")
	}
	return r.all(`SELECT u.id,u.student_id,u.full_name,e.batch_id
		FROM users u JOIN division_students e ON e.student_user_id=u.id WHERE e.division_id=$1 ORDER BY u.student_id`, division)
}
