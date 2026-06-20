export type Role = "teacher" | "admin";

export type NavKey =
  | "dashboard"
  | "sessions"
  | "export"
  | "students"
  | "password"
  | "teachers"
  | "admins"
  | "subjects"
  | "schedule";

export type SessionStatus = "active" | "locked" | "editable" | "ended";

export interface TeacherScheduleSlot {
  id: string;
  time_start: string;
  time_end: string;
  subject_name: string;
  subject_code: string;
  division_label: string;
  batch_label: string | null;
  room: string | null;
  assignment_id: number;
}

export interface TeacherAssignment {
  id: number;
  teacher_user_id: string;
  teacher_name: string;
  subject_id: number;
  subject_name: string;
  subject_code: string;
  division_id: number;
  division_label: string;
  batch_id: number | null;
  batch_label: string | null;
}

export interface TeacherSession {
  id: string;
  subject: string;
  assignment_id: number | null;
  starts_at: string;
  ends_at: string | null;
  is_active: boolean;
  finalization_open: boolean;
  attendance_locked: boolean;
  room?: string | null;
  division?: string | null;
  batch?: string | null;
  present_students?: number;
  total_students?: number;
}

export interface AttendanceRecord {
  student_user_id: string;
  student_id?: string | null;
  student_name: string;
  detection_count: number;
  presence_ratio: number;
  is_present: boolean;
  biometric_verified: boolean;
  overridden_by_teacher: boolean;
  override_reason?: string | null;
}

export interface AttendanceSummary {
  session_id: string;
  subject: string;
  starts_at: string;
  ends_at: string | null;
  total_students: number;
  present_students: number;
  records: AttendanceRecord[];
}

export interface AdminTeacher {
  id: string;
  teacher_id: string;
  full_name: string;
}

export interface AdminAccount {
  id: string;
  admin_id: string;
  full_name: string;
  is_super_admin: boolean;
}

export interface SubjectItem {
  id: number;
  code: string;
  name: string;
  subject_type: "lecture" | "lab";
}

export interface SemesterItem {
  id: number;
  name: string;
  start_date: string;
  end_date: string;
  is_active: boolean;
}

export interface BranchItem {
  id: number;
  code: string;
  name: string;
}

export interface DivisionItem {
  id: number;
  branch_id: number;
  year: number;
  div_number: number;
  label: string;
  branch_code: string;
}

export interface BatchItem {
  id: number;
  division_id: number;
  label: string;
}

export interface StudentItem {
  id: string;
  student_id: string;
  full_name: string;
  batch_id: number | null;
}
