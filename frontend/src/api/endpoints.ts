import api from './client'

// Auth
export const login = (identifier: string, password: string) =>
  api.post('/auth/login', { identifier, password }).then(r => r.data)

export const getMe = () => api.get('/auth/me').then(r => r.data)

// Teacher
export const getTodaySchedule = () => api.get('/teacher/me/schedule/today').then(r => r.data)
export const getMyAssignments = () => api.get('/teacher/me/assignments').then(r => r.data)
export const getMySessions = (params?: Record<string, string | number>) =>
  api.get('/teacher/me/sessions', { params }).then(r => r.data)

export const getAttendanceSummary = (sessionId: string) =>
  api.get(`/teacher/sessions/${sessionId}/attendance-summary`).then(r => r.data)

export const overrideAttendance = (sessionId: string, data: { student_user_id: string; is_present: boolean; reason: string }) =>
  api.post(`/teacher/sessions/${sessionId}/attendance/override`, data).then(r => r.data)

export const lockAttendance = (sessionId: string) =>
  api.post(`/teacher/sessions/${sessionId}/lock`).then(r => r.data)

export const exportAttendance = (assignmentId: number, fromDate: string, toDate: string) =>
  api.get('/teacher/attendance/export', {
    params: { assignment_id: assignmentId, from_date: fromDate, to_date: toDate },
    responseType: 'blob',
  })

export const addStudent = (data: { full_name: string; student_id: string; division_id?: number; batch_id?: number }) =>
  api.post('/teacher/students', data).then(r => r.data)

export const getDivisionStudents = (divisionId: number) =>
  api.get(`/teacher/divisions/${divisionId}/students`).then(r => r.data)

// Admin
export const adminListTeachers = () => api.get('/admin/teachers').then(r => r.data)
export const adminCreateTeacher = (data: { full_name: string; teacher_id: string; password: string }) =>
  api.post('/admin/teachers', data).then(r => r.data)

export const adminListAdmins = () => api.get('/admin/admins').then(r => r.data)
export const adminCreateAdmin = (data: { full_name: string; admin_id: string; password: string; is_super_admin: boolean }) =>
  api.post('/admin/admins', data).then(r => r.data)

export const listSemesters = () => api.get('/admin/semesters').then(r => r.data)
export const createSemester = (data: { name: string; start_date: string; end_date: string; is_active: boolean }) =>
  api.post('/admin/semesters', data).then(r => r.data)
export const activateSemester = (id: number) => api.patch(`/admin/semesters/${id}/activate`).then(r => r.data)

export const listBranches = () => api.get('/admin/branches').then(r => r.data)
export const createBranch = (data: { code: string; name: string }) =>
  api.post('/admin/branches', data).then(r => r.data)

export const listDivisions = (branchId?: number) =>
  api.get('/admin/divisions', { params: branchId ? { branch_id: branchId } : {} }).then(r => r.data)
export const createDivision = (data: { branch_id: number; year: number; div_number: number; label: string }) =>
  api.post('/admin/divisions', data).then(r => r.data)

export const listBatches = (divisionId?: number) =>
  api.get('/admin/batches', { params: divisionId ? { division_id: divisionId } : {} }).then(r => r.data)
export const createBatch = (data: { division_id: number; label: string }) =>
  api.post('/admin/batches', data).then(r => r.data)

export const listSubjects = () => api.get('/admin/subjects').then(r => r.data)
export const createSubject = (data: { code: string; name: string; subject_type: string }) =>
  api.post('/admin/subjects', data).then(r => r.data)

export const listAssignments = (params?: { teacher_id?: string; division_id?: number }) =>
  api.get('/admin/assignments', { params }).then(r => r.data)
export const createAssignment = (data: { teacher_user_id: string; subject_id: number; division_id: number; batch_id?: number }) =>
  api.post('/admin/assignments', data).then(r => r.data)
export const deleteAssignment = (id: number) => api.delete(`/admin/assignments/${id}`)

export const listSlots = (params?: { semester_id?: number; division_id?: number; teacher_id?: string }) =>
  api.get('/admin/schedule-slots', { params }).then(r => r.data)
export const createSlot = (data: object) => api.post('/admin/schedule-slots', data).then(r => r.data)
export const updateSlot = (id: number, data: object) => api.put(`/admin/schedule-slots/${id}`, data).then(r => r.data)
export const deleteSlot = (id: number) => api.delete(`/admin/schedule-slots/${id}`)

export const adminCreateStudent = (data: { full_name: string; student_id: string; division_id?: number; batch_id?: number }) =>
  api.post('/admin/students', data).then(r => r.data)
