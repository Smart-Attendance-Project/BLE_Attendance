import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, Clock, Fingerprint, Lock, ListChecks, MapPin, Search } from "lucide-react";
import {
  getMyAssignments,
  getMySessions,
  getAttendanceSummary,
  overrideAttendance,
  lockAttendance,
} from "../../../api/endpoints";
import { Button } from "../../ui/button";
import { PageHeader, Panel, EmptyState } from "../../components/shared/Primitives";
import { StatusChip } from "../../components/shared/StatusChip";
import type { AttendanceSummary, TeacherAssignment, TeacherSession } from "../../lib/types";

function fmtDate(iso: string) {
  return new Date(iso).toLocaleDateString("en-IN", { dateStyle: "medium" });
}

function fmtTime(iso: string) {
  return new Date(iso).toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit" });
}

export function Sessions() {
  const qc = useQueryClient();
  const [query, setQuery] = useState("");
  const [selectedAssignment, setSelectedAssignment] = useState<number | null>(null);
  const [selectedSession, setSelectedSession] = useState<string | null>(null);
  const [overrideReason, setOverrideReason] = useState("");

  const { data: assignments = [] } = useQuery({
    queryKey: ["my-assignments"],
    queryFn: getMyAssignments,
    refetchInterval: 60_000,
  });

  const { data: sessions = [] } = useQuery({
    queryKey: ["my-sessions", selectedAssignment],
    queryFn: () => getMySessions(selectedAssignment ? { assignment_id: selectedAssignment } : undefined),
    refetchInterval: 30_000,
  });

  const filteredAssignments = useMemo(() => {
    const text = query.trim().toLowerCase();
    return (assignments as TeacherAssignment[]).filter((a) =>
      `${a.subject_code} ${a.subject_name} ${a.division_label} ${a.batch_label ?? ""}`.toLowerCase().includes(text)
    );
  }, [assignments, query]);

  const selectedAssignmentData = (assignments as TeacherAssignment[]).find((a) => a.id === selectedAssignment) ?? null;
  const selectedSessionData = (sessions as TeacherSession[]).find((s) => s.id === selectedSession) ?? null;

  const { data: summary } = useQuery({
    queryKey: ["attendance-summary", selectedSession],
    queryFn: () => getAttendanceSummary(selectedSession!),
    enabled: !!selectedSession,
    refetchInterval: 15_000,
  });

  const summaryData = summary as AttendanceSummary | undefined;
  const editable = selectedSessionData ? selectedSessionData.is_active || selectedSessionData.finalization_open : false;

  const overrideMut = useMutation({
    mutationFn: ({ studentId, isPresent }: { studentId: string; isPresent: boolean }) =>
      overrideAttendance(selectedSession!, {
        student_user_id: studentId,
        is_present: isPresent,
        reason: overrideReason || "Manual override",
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["attendance-summary", selectedSession] }),
  });

  const lockMut = useMutation({
    mutationFn: () => lockAttendance(selectedSession!),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["my-sessions", selectedAssignment] });
      qc.invalidateQueries({ queryKey: ["attendance-summary", selectedSession] });
    },
  });

  // Session detail view (attendance table)
  if (selectedSession && summaryData) {
    return (
      <>
        <PageHeader
          back={
            <button onClick={() => setSelectedSession(null)} className="mb-1 inline-flex items-center gap-1.5 text-sm text-primary hover:text-[#0f766e] font-medium transition-colors">
              <ArrowLeft className="size-4" /> Back to sessions
            </button>
          }
          title={`${summaryData.subject}`}
          subtitle={`${fmtDate(summaryData.starts_at)} · ${summaryData.records.length} students`}
          actions={
            <div className="flex items-center gap-2">
              {selectedSessionData?.attendance_locked ? <StatusChip tone="locked">Locked</StatusChip> : editable ? <StatusChip tone="editable">Editable</StatusChip> : <StatusChip tone="ended">Closed</StatusChip>}
              {!selectedSessionData?.attendance_locked && selectedSessionData?.is_active && (
                <Button variant="outline" className="rounded-lg" onClick={() => lockMut.mutate()}>
                  <Lock className="size-4" /> Lock attendance
                </Button>
              )}
            </div>
          }
        />

        <div className="mb-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <Panel><p className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-2">Present</p><p className="text-3xl font-semibold text-primary">{summaryData.present_students}/{summaryData.total_students}</p></Panel>
          <Panel><p className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-2">Date</p><p className="text-3xl font-semibold text-foreground">{fmtDate(summaryData.starts_at)}</p></Panel>
          <Panel><p className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-2">Session</p><p className="text-3xl font-semibold text-blue-500">{fmtTime(summaryData.starts_at)}</p></Panel>
          <Panel><p className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-2">Status</p><p className="text-3xl font-semibold text-foreground">{selectedSessionData?.is_active ? "Active" : selectedSessionData?.attendance_locked ? "Locked" : "Ended"}</p></Panel>
        </div>

        {editable && (
          <div className="mb-4 max-w-md">
            <input
              placeholder="Override reason (optional)"
              value={overrideReason}
              onChange={(e) => setOverrideReason(e.target.value)}
              className="h-11 w-full rounded-lg border border-slate-200 bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-1 focus:ring-primary"
            />
          </div>
        )}

        <Panel className="overflow-hidden p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-sm text-left border-collapse">
              <thead>
                <tr className="bg-slate-50 border-b border-slate-200">
                  <th className="px-6 py-4 text-[10px] font-bold text-primary uppercase tracking-widest">Student</th>
                  <th className="px-6 py-4 text-[10px] font-bold text-primary uppercase tracking-widest">Batch</th>
                  <th className="px-6 py-4 text-[10px] font-bold text-primary uppercase tracking-widest">Detections</th>
                  <th className="px-6 py-4 text-[10px] font-bold text-primary uppercase tracking-widest">Ratio</th>
                  <th className="px-6 py-4 text-[10px] font-bold text-primary uppercase tracking-widest">Biometric</th>
                  <th className="px-6 py-4 text-[10px] font-bold text-primary uppercase tracking-widest text-center">Status</th>
                  <th className="px-6 py-4 text-[10px] font-bold text-primary uppercase tracking-widest text-right">Override</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-200">
                {summaryData.records.map((r) => (
                  <tr key={r.student_user_id} className="hover:bg-slate-50 transition-colors">
                    <td className="px-6 py-4">
                      <div className="leading-tight">
                        <p className="text-sm font-medium text-foreground">{r.student_name}</p>
                        <p className="text-[10px] text-muted-foreground font-bold uppercase">{r.student_id ?? r.student_user_id}</p>
                      </div>
                    </td>
                    <td className="px-6 py-4 text-sm text-muted-foreground">{selectedAssignmentData?.batch_label ?? "All"}</td>
                    <td className="px-6 py-4 text-sm text-muted-foreground">{r.detection_count}</td>
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-3">
                        <div className="h-1.5 w-[100px] rounded bg-slate-100">
                          <div className="h-full rounded bg-primary" style={{ width: `${Math.round(r.presence_ratio * 100)}%` }} />
                        </div>
                        <span className="tabular-nums text-xs text-muted-foreground">{Math.round(r.presence_ratio * 100)}%</span>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      {r.biometric_verified ? (
                        <span className="inline-flex items-center gap-1 text-sm text-emerald-600"><Fingerprint className="size-4" /> Verified</span>
                      ) : (
                        <span className="text-sm text-muted-foreground/40">—</span>
                      )}
                    </td>
                    <td className="px-6 py-4 text-center">
                      <StatusChip tone={r.is_present ? "present" : "absent"}>{r.is_present ? "Present" : "Absent"}</StatusChip>
                    </td>
                    <td className="px-6 py-4 text-right">
                      <Button
                        variant={r.is_present ? "outline" : "default"}
                        size="sm"
                        disabled={!editable}
                        className="rounded-lg"
                        onClick={() => overrideMut.mutate({ studentId: r.student_user_id, isPresent: !r.is_present })}
                      >
                        Mark {r.is_present ? "Absent" : "Present"}
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Panel>
      </>
    );
  }

  // Assignment session list view
  if (selectedAssignmentData) {
    const assignmentSessions = (sessions as TeacherSession[]).filter((s) => s.assignment_id === selectedAssignmentData.id);

    return (
      <>
        <PageHeader
          back={
            <button onClick={() => setSelectedAssignment(null)} className="mb-1 inline-flex items-center gap-1.5 text-sm text-primary hover:text-[#0f766e] font-medium transition-colors">
              <ArrowLeft className="size-4" /> Back to assignments
            </button>
          }
          title={selectedAssignmentData.subject_name}
          subtitle={`${selectedAssignmentData.subject_code} · ${selectedAssignmentData.division_label}${selectedAssignmentData.batch_label ? ` · Batch ${selectedAssignmentData.batch_label}` : ""}`}
        />

        {assignmentSessions.length === 0 ? (
          <EmptyState
            icon={<ListChecks className="size-6" />}
            title="No sessions recorded yet"
            description="Once you start attendance, the session history will appear here."
          />
        ) : (
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {assignmentSessions.map((s) => (
              <button
                key={s.id}
                onClick={() => setSelectedSession(s.id)}
                className="rounded-lg border border-slate-200 bg-white p-5 text-left transition-all shadow-sm hover:shadow-md hover:border-primary/40"
              >
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="text-foreground font-medium">{fmtDate(s.starts_at)}</p>
                    <p className="mt-1 text-sm text-muted-foreground">
                      {fmtTime(s.starts_at)}{s.ends_at ? ` - ${fmtTime(s.ends_at)}` : ""}
                    </p>
                  </div>
                  <StatusChip tone={s.attendance_locked ? "locked" : s.is_active ? "active" : "ended"} />
                </div>
                <div className="mt-4 flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
                  <span className="inline-flex items-center gap-1"><Clock className="size-4" /> {s.room ?? "Room"}</span>
                  {s.finalization_open && <StatusChip tone="warning">Finalization open</StatusChip>}
                </div>
              </button>
            ))}
          </div>
        )}
      </>
    );
  }

  // Assignment list view (main sessions page)
  return (
    <>
      <PageHeader
        title="Attendance Sessions"
        subtitle="Grouped by assignment, then drilled into by session."
        actions={
          <div className="relative w-full md:w-80">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <Search className="size-4 text-muted-foreground" />
            </div>
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search classes"
              className="block w-full h-11 pl-10 pr-3 py-2.5 border border-slate-200 rounded-lg bg-white text-sm text-foreground outline-none transition placeholder:text-muted-foreground focus:border-primary focus:ring-1 focus:ring-primary"
            />
          </div>
        }
      />

      {filteredAssignments.length === 0 ? (
        <EmptyState
          icon={<ListChecks className="size-6" />}
          title="No matching assignments"
          description="Try a different subject, division, or batch."
        />
      ) : (
        <div className="grid gap-6 md:grid-cols-2 xl:grid-cols-3">
          {filteredAssignments.map((a) => {
            const count = (sessions as TeacherSession[]).filter((s) => s.assignment_id === a.id).length;
            return (
              <button
                key={a.id}
                onClick={() => setSelectedAssignment(a.id)}
                className="rounded-lg border border-slate-200 bg-white p-5 text-left transition-all shadow-sm hover:shadow-md hover:border-primary/40 cursor-pointer group"
              >
                <div className="flex items-start justify-between gap-3 mb-1">
                  <h3 className="text-lg font-bold text-foreground group-hover:text-primary transition-colors">{a.subject_name}</h3>
                  <StatusChip tone={a.batch_label ? "lab" : "lecture"}>{a.batch_label ? "Practical" : "Lecture"}</StatusChip>
                </div>
                <p className="text-sm text-muted-foreground font-medium mb-6">{a.subject_code}</p>
                <div className="flex items-center justify-between text-sm font-medium text-muted-foreground">
                  <span>{a.division_label}{a.batch_label ? ` · Batch ${a.batch_label}` : ""}</span>
                  <span className="text-primary">{count} session{count === 1 ? "" : "s"}</span>
                </div>
              </button>
            );
          })}
        </div>
      )}
    </>
  );
}
