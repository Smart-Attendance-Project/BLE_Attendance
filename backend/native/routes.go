package main

import "net/http"

func (s *server) routes() {
	s.route(http.MethodGet, "/health", "", func(*request) any { return object{"status": "ok"} })
	s.route(http.MethodPost, "/auth/register", "", register)
	s.route(http.MethodPost, "/auth/login", "", s.login)
	s.route(http.MethodGet, "/auth/me", "user", func(r *request) any { return r.user })
	s.route(http.MethodPost, "/auth/change-password", "user", changePassword)
	s.route(http.MethodPost, "/auth/register-face", "user", func(r *request) any { return storeFace(r, false) })
	s.route(http.MethodGet, "/auth/face-profile", "user", faceProfile)
	s.route(http.MethodPost, "/auth/re-register-face", "user", func(r *request) any { return storeFace(r, true) })

	s.route(http.MethodPost, "/sessions", "teacher", startSession)
	s.route(http.MethodPost, "/sessions/{session_id}/end", "teacher", endSession)
	s.route(http.MethodGet, "/sessions/active", "user", activeSession)
	s.route(http.MethodPost, "/teacher/sessions/{session_id}/open-finalization", "teacher", openFinalization)
	s.route(http.MethodPost, "/detections", "student", detection)
	s.route(http.MethodPost, "/detections/batch", "teacher", detectionBatch)
	s.route(http.MethodPost, "/attendance/finalize", "student", finalizeAttendance)
	s.route(http.MethodGet, "/teacher/sessions/{session_id}/attendance-summary", "teacher", attendanceSummary)
	s.route(http.MethodPost, "/teacher/sessions/{session_id}/attendance/override", "teacher", overrideAttendance)
	s.route(http.MethodPost, "/teacher/sessions/{session_id}/lock", "teacher", lockAttendance)
	s.route(http.MethodGet, "/teacher/sessions/{session_id}/detections", "teacher", sessionDetections)

	s.route(http.MethodGet, "/teacher/me/schedule/today", "teacher", teacherSchedule)
	s.route(http.MethodGet, "/teacher/me/assignments", "teacher", func(r *request) any {
		return r.all(assignmentSelect+" WHERE a.teacher_user_id=$1", r.user["id"])
	})
	s.route(http.MethodGet, "/teacher/me/sessions", "teacher", teacherSessions)
	s.route(http.MethodGet, "/teacher/attendance/export", "teacher", exportAttendance)
	s.route(http.MethodPost, "/teacher/students", "teacher", addStudent)
	s.route(http.MethodGet, "/teacher/me/divisions", "teacher", teacherDivisions)
	s.route(http.MethodGet, "/teacher/divisions/{division_id}/students", "teacher", divisionStudents)

	s.route(http.MethodPost, "/admin/teachers", "admin", addTeacher)
	s.route(http.MethodGet, "/admin/teachers", "admin", func(r *request) any {
		return r.all("SELECT id,full_name,teacher_id FROM users WHERE role='teacher'")
	})
	s.route(http.MethodPost, "/admin/admins", "admin", addAdmin)
	s.route(http.MethodGet, "/admin/admins", "admin", func(r *request) any {
		return r.all("SELECT id,full_name,admin_id,is_super_admin FROM users WHERE role='admin'")
	})
	s.route(http.MethodPost, "/admin/semesters", "admin", createSemester)
	s.route(http.MethodGet, "/admin/semesters", "user", func(r *request) any {
		return r.all("SELECT " + semesterFields + " FROM semesters ORDER BY id DESC")
	})
	s.route(http.MethodPatch, "/admin/semesters/{sem_id}/activate", "admin", activateSemester)
	s.route(http.MethodPost, "/admin/branches", "admin", createBranch)
	s.route(http.MethodGet, "/admin/branches", "user", func(r *request) any {
		return r.all("SELECT " + branchFields + " FROM branches ORDER BY code")
	})
	s.route(http.MethodPost, "/admin/divisions", "admin", createDivision)
	s.route(http.MethodGet, "/admin/divisions", "user", listDivisions)
	s.route(http.MethodPost, "/admin/batches", "admin", createBatch)
	s.route(http.MethodGet, "/admin/batches", "user", listBatches)
	s.route(http.MethodPost, "/admin/subjects", "admin", createSubject)
	s.route(http.MethodGet, "/admin/subjects", "user", func(r *request) any {
		return r.all("SELECT " + subjectFields + " FROM subjects ORDER BY code")
	})
	s.route(http.MethodPost, "/admin/assignments", "admin", createAssignment)
	s.route(http.MethodGet, "/admin/assignments", "user", listAssignments)
	s.route(http.MethodDelete, "/admin/assignments/{assignment_id}", "admin", deleteAssignment)
	s.route(http.MethodPost, "/admin/schedule-slots", "admin", createSlot)
	s.route(http.MethodGet, "/admin/schedule-slots", "user", listSlots)
	s.route(http.MethodPut, "/admin/schedule-slots/{slot_id}", "admin", updateSlot)
	s.route(http.MethodDelete, "/admin/schedule-slots/{slot_id}", "admin", deleteSlot)
	s.route(http.MethodPost, "/admin/students", "admin", addStudent)
	s.route(http.MethodPost, "/admin/division-students", "admin", assignStudent)
	s.route(http.MethodPost, "/admin/sessions/{session_id}/attendance/override", "admin", overrideAttendance)
	s.route(http.MethodPost, "/teacher/sessions/{session_id}/attendance/batch-submit", "teacher", batchAttendance)
	s.route(http.MethodGet, "/teacher/me/schedule/today/slots", "teacher", teacherMobileSchedule)
}
