package main

import (
	"fmt"
	"strings"
)

const semesterFields = "id, name, start_date::text AS start_date, end_date::text AS end_date, is_active"
const branchFields = "id, code, name"
const batchFields = "id, division_id, label"
const subjectFields = "id, code, name, subject_type"

const divisionSelect = `SELECT d.id, d.branch_id, d.year, d.div_number, d.label, d.start_student_id, d.end_student_id,
	COALESCE(b.code, '') AS branch_code FROM divisions d LEFT JOIN branches b ON b.id=d.branch_id`

const assignmentSelect = `SELECT a.id,a.teacher_user_id,COALESCE(u.full_name, '') AS teacher_name,
	a.subject_id,COALESCE(s.name, '') AS subject_name,COALESCE(s.code, '') AS subject_code,
	a.division_id,COALESCE(d.label, '') AS division_label,a.batch_id,b.label AS batch_label
	FROM teacher_assignments a
	LEFT JOIN users u ON u.id=a.teacher_user_id LEFT JOIN subjects s ON s.id=a.subject_id
	LEFT JOIN divisions d ON d.id=a.division_id LEFT JOIN batches b ON b.id=a.batch_id`

const slotSelect = `SELECT l.id,l.assignment_id,l.semester_id,l.day_of_week,l.time_start,l.time_end,l.room,
	COALESCE(s.name, '') AS subject_name,COALESCE(s.code, '') AS subject_code,COALESCE(d.label, '') AS division_label,
	b.label AS batch_label,COALESCE(u.full_name, '') AS teacher_name
	FROM schedule_slots l JOIN teacher_assignments a ON a.id=l.assignment_id
	LEFT JOIN subjects s ON s.id=a.subject_id LEFT JOIN divisions d ON d.id=a.division_id
	LEFT JOIN batches b ON b.id=a.batch_id LEFT JOIN users u ON u.id=a.teacher_user_id`

type conditions struct {
	filters []string
	args    []any
}

func (c *conditions) add(column, operator string, value any) {
	if value != nil {
		c.args = append(c.args, value)
		c.filters = append(c.filters, fmt.Sprintf("%s %s $%d", column, operator, len(c.args)))
	}
}

func (c *conditions) where() string {
	if len(c.filters) == 0 {
		return ""
	}
	return " WHERE " + strings.Join(c.filters, " AND ")
}

func createSemester(r *request) any {
	return r.transaction(func() any {
		body := r.args()
		if flag(body["is_active"]) {
			r.exec("UPDATE semesters SET is_active=false")
		}
		return r.one(`INSERT INTO semesters (name,start_date,end_date,is_active)
			VALUES ($1,$2::text::date,$3::text::date,$4) RETURNING `+semesterFields,
			body["name"], body["start_date"], body["end_date"], body["is_active"])
	})
}

func activateSemester(r *request) any {
	return r.transaction(func() any {
		r.exec("UPDATE semesters SET is_active=false")
		row := r.one("UPDATE semesters SET is_active=true WHERE id=$1 RETURNING "+semesterFields, r.path["sem_id"])
		if row == nil {
			fail(404, "Semester not found")
		}
		return row
	})
}

func createBranch(r *request) any {
	body := r.args()
	return r.one("INSERT INTO branches (code,name) VALUES ($1,$2) RETURNING "+branchFields, body["code"], body["name"])
}

func createDivision(r *request) any {
	body := r.args()
	return r.transaction(func() any {
		row := r.one(`INSERT INTO divisions (branch_id,year,div_number,label,start_student_id,end_student_id)
			VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
			body["branch_id"], body["year"], body["div_number"], body["label"], body["start_student_id"], body["end_student_id"])
		return r.one(divisionSelect+" WHERE d.id=$1", row["id"])
	})
}

func listDivisions(r *request) any {
	filter := conditions{}
	filter.add("d.branch_id", "=", r.query["branch_id"])
	return r.all(divisionSelect+filter.where()+" ORDER BY d.year,d.div_number", filter.args...)
}

func createBatch(r *request) any {
	body := r.args()
	return r.one("INSERT INTO batches (division_id,label) VALUES ($1,$2) RETURNING "+batchFields, body["division_id"], body["label"])
}

func listBatches(r *request) any {
	filter := conditions{}
	filter.add("division_id", "=", r.query["division_id"])
	return r.all("SELECT "+batchFields+" FROM batches"+filter.where()+" ORDER BY label", filter.args...)
}

func createSubject(r *request) any {
	body := r.args()
	return r.one("INSERT INTO subjects (code,name,subject_type) VALUES ($1,$2,$3) RETURNING "+subjectFields,
		body["code"], body["name"], body["subject_type"])
}

func createAssignment(r *request) any {
	body := r.args()
	return r.transaction(func() any {
		row := r.one(`INSERT INTO teacher_assignments (teacher_user_id,subject_id,division_id,batch_id)
			VALUES ($1,$2,$3,$4) RETURNING id`, body["teacher_user_id"], body["subject_id"], body["division_id"], body["batch_id"])
		return r.one(assignmentSelect+" WHERE a.id=$1", row["id"])
	})
}

func listAssignments(r *request) any {
	filter := conditions{}
	filter.add("a.teacher_user_id", "=", r.query["teacher_id"])
	filter.add("a.division_id", "=", r.query["division_id"])
	return r.all(assignmentSelect+filter.where(), filter.args...)
}

func deleteAssignment(r *request) any {
	if r.exec("DELETE FROM teacher_assignments WHERE id=$1", r.path["assignment_id"]) == 0 {
		fail(404, "Not found")
	}
	return message("Deleted")
}

func createSlot(r *request) any {
	body := r.args()
	return r.transaction(func() any {
		row := r.one(`INSERT INTO schedule_slots (assignment_id,semester_id,day_of_week,time_start,time_end,room)
			VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`, body["assignment_id"], body["semester_id"], body["day_of_week"],
			body["time_start"], body["time_end"], body["room"])
		return r.one(slotSelect+" WHERE l.id=$1", row["id"])
	})
}

func listSlots(r *request) any {
	filter := conditions{}
	filter.add("l.semester_id", "=", r.query["semester_id"])
	filter.add("a.division_id", "=", r.query["division_id"])
	filter.add("a.teacher_user_id", "=", r.query["teacher_id"])
	return r.all(slotSelect+filter.where()+" ORDER BY l.time_start", filter.args...)
}

func updateSlot(r *request) any {
	body := r.args()
	return r.transaction(func() any {
		row := r.one(`UPDATE schedule_slots SET assignment_id=$2,semester_id=$3,day_of_week=$4,time_start=$5,time_end=$6,room=$7
			WHERE id=$1 RETURNING id`, r.path["slot_id"], body["assignment_id"], body["semester_id"], body["day_of_week"],
			body["time_start"], body["time_end"], body["room"])
		if row == nil {
			fail(404, "Not found")
		}
		return r.one(slotSelect+" WHERE l.id=$1", row["id"])
	})
}

func deleteSlot(r *request) any {
	if r.exec("DELETE FROM schedule_slots WHERE id=$1", r.path["slot_id"]) == 0 {
		fail(404, "Not found")
	}
	return message("Deleted")
}

func assignStudent(r *request) any {
	body := r.args()
	r.exec(`INSERT INTO division_students (student_user_id,division_id,batch_id) VALUES ($1,$2,$3)
		ON CONFLICT (student_user_id,division_id) DO UPDATE SET batch_id=EXCLUDED.batch_id`,
		body["student_user_id"], body["division_id"], body["batch_id"])
	return message("Assigned")
}
