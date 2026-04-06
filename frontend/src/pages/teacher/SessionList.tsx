import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useSearchParams } from 'react-router-dom'
import { getMySessions, getMyAssignments, getAttendanceSummary, overrideAttendance } from '../../api/endpoints'
import { CheckCircle, XCircle, AlertCircle, ChevronLeft, Users, BookOpen } from 'lucide-react'

function isEditable(session: any): boolean {
  if (session.attendance_locked) return false
  if (session.is_active) return true
  const ended = session.ends_at ? new Date(session.ends_at).getTime() : 0
  return Date.now() - ended < 24 * 60 * 60 * 1000
}

export default function SessionList() {
  const [params] = useSearchParams()
  const assignmentId = params.get('assignment_id')
  const [selectedAssignment, setSelectedAssignment] = useState<number | null>(
    assignmentId ? Number(assignmentId) : null
  )
  const [selectedSession, setSelectedSession] = useState<string | null>(null)
  const [overrideReason, setOverrideReason] = useState('')
  const qc = useQueryClient()

  const { data: assignments = [] } = useQuery({ queryKey: ['my-assignments'], queryFn: getMyAssignments })

  const { data: sessions = [] } = useQuery({
    queryKey: ['sessions', selectedAssignment],
    queryFn: () => getMySessions(selectedAssignment ? { assignment_id: selectedAssignment } : undefined),
    enabled: !!selectedAssignment,
  })

  const { data: summary } = useQuery({
    queryKey: ['summary', selectedSession],
    queryFn: () => getAttendanceSummary(selectedSession!),
    enabled: !!selectedSession,
  })

  const overrideMut = useMutation({
    mutationFn: ({ studentId, isPresent }: { studentId: string; isPresent: boolean }) =>
      overrideAttendance(selectedSession!, {
        student_user_id: studentId, is_present: isPresent,
        reason: overrideReason || 'Manual override',
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['summary', selectedSession] }),
  })

  const selectedSessionData = sessions.find((s: any) => s.id === selectedSession)
  const editable = selectedSessionData ? isEditable(selectedSessionData) : false

  const assignmentsBySubject = assignments.reduce((acc: any, a: any) => {
    const key = a.subject_code
    if (!acc[key]) acc[key] = { subject_name: a.subject_name, subject_code: a.subject_code, items: [] }
    acc[key].items.push(a)
    return acc
  }, {})

  // ── Student attendance detail ──
  if (selectedSession && summary) {
    return (
      <div className="p-8 max-w-5xl mx-auto">
        <button onClick={() => setSelectedSession(null)}
          className="flex items-center gap-2 text-base text-zinc-500 hover:text-zinc-900 mb-6 transition-colors font-medium">
          <ChevronLeft size={18} /> Back to sessions
        </button>

        <div className="bg-zinc-50 border-2 border-black rounded-xl p-6 mb-6 shadow-[4px_4px_0_0_#000] flex items-center justify-between gap-4 flex-wrap">
          <div>
            <h2 className="font-black text-zinc-900 text-2xl">{summary.subject}</h2>
            <p className="text-base text-zinc-500 mt-1">{new Date(summary.starts_at).toLocaleDateString('en-IN', { dateStyle: 'full' })}</p>
          </div>
          <div className="flex items-center gap-5">
            <div className="text-center">
              <div className="text-4xl font-black text-zinc-900">{summary.present_students}<span className="text-zinc-400 font-normal text-2xl">/{summary.total_students}</span></div>
              <div className="text-sm text-zinc-500 font-medium mt-0.5">Present</div>
            </div>
            {!editable && (
              <span className="bg-zinc-100 border-2 border-zinc-300 text-zinc-500 text-sm font-bold px-4 py-2 rounded-lg">
                {selectedSessionData?.attendance_locked ? 'Locked' : 'Editing closed'}
              </span>
            )}
          </div>
        </div>

        {editable && (
          <div className="mb-5">
            <input placeholder="Override reason (optional)"
              value={overrideReason} onChange={e => setOverrideReason(e.target.value)}
              className="border-2 border-black rounded-lg px-4 py-2.5 text-base w-80 focus:outline-none focus:ring-2 focus:ring-indigo-400 shadow-[2px_2px_0_0_#000] bg-zinc-50" />
          </div>
        )}

        <div className="bg-zinc-50 border-2 border-black rounded-xl overflow-hidden shadow-[4px_4px_0_0_#000]">
          <table className="w-full text-base">
            <thead>
              <tr className="bg-zinc-900 text-white">
                {['Student ID', 'Name', 'Detections', 'Ratio', 'Status', 'Biometric', ''].map(h => (
                  <th key={h} className="px-5 py-4 text-left text-sm font-bold uppercase tracking-wider">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-200">
              {summary.records.map((r: any) => (
                <tr key={r.student_user_id} className={r.is_present ? 'bg-green-50' : 'bg-red-50/40'}>
                  <td className="px-5 py-3 font-mono text-sm text-zinc-500">{r.student_id}</td>
                  <td className="px-5 py-3 font-semibold text-zinc-900">{r.student_name}</td>
                  <td className="px-5 py-3 text-zinc-600">{r.detection_count}</td>
                  <td className="px-5 py-3 text-zinc-600">{(r.presence_ratio * 100).toFixed(0)}%</td>
                  <td className="px-5 py-3">
                    <span className={`inline-flex items-center gap-1.5 text-sm font-bold px-3 py-1 rounded-lg border-2 ${r.is_present ? 'bg-green-100 text-green-800 border-green-400' : 'bg-red-100 text-red-800 border-red-400'}`}>
                      {r.is_present ? <CheckCircle size={14} /> : <XCircle size={14} />}
                      {r.is_present ? 'Present' : 'Absent'}
                      {r.overridden_by_teacher && <AlertCircle size={12} className="opacity-60" />}
                    </span>
                  </td>
                  <td className="px-5 py-3 text-zinc-500 text-sm">{r.biometric_verified ? 'Verified' : 'No'}</td>
                  <td className="px-5 py-3">
                    <button
                      disabled={!editable}
                      onClick={() => overrideMut.mutate({ studentId: r.student_user_id, isPresent: !r.is_present })}
                      className="text-sm px-4 py-2 rounded-lg border-2 border-black font-bold bg-zinc-50 hover:bg-indigo-100 disabled:opacity-30 disabled:cursor-not-allowed disabled:hover:bg-zinc-50 transition-colors shadow-[2px_2px_0_0_#000] disabled:shadow-none">
                      Mark {r.is_present ? 'Absent' : 'Present'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    )
  }

  // ── Session list for a class ──
  if (selectedAssignment && !selectedSession) {
    const assignment = assignments.find((a: any) => a.id === selectedAssignment)
    return (
      <div className="p-8 max-w-5xl mx-auto">
        <button onClick={() => setSelectedAssignment(null)}
          className="flex items-center gap-2 text-base text-zinc-500 hover:text-zinc-900 mb-6 transition-colors font-medium">
          <ChevronLeft size={18} /> Back to classes
        </button>

        <div className="mb-6">
          <h1 className="text-3xl font-black text-zinc-900">{assignment?.subject_name}</h1>
          <p className="text-zinc-500 text-base mt-1">{assignment?.division_label}{assignment?.batch_label ? ` / Batch ${assignment.batch_label}` : ''}</p>
        </div>

        {sessions.length === 0 && (
          <div className="border-2 border-dashed border-zinc-300 rounded-xl py-16 text-center text-zinc-400">
            <BookOpen size={40} className="mx-auto mb-4 opacity-40" />
            <p className="font-semibold text-lg">No sessions recorded yet for this class</p>
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
          {sessions.map((s: any) => {
            const editable = isEditable(s)
            return (
              <button key={s.id} onClick={() => setSelectedSession(s.id)}
                className="text-left bg-zinc-50 border-2 border-black rounded-xl p-5 shadow-[4px_4px_0_0_#000] hover:shadow-[2px_2px_0_0_#000] hover:translate-x-0.5 hover:translate-y-0.5 transition-all">
                <div className="font-black text-zinc-900 text-lg">{new Date(s.starts_at).toLocaleDateString('en-IN', { dateStyle: 'medium' })}</div>
                <div className="text-sm text-zinc-500 mt-1">{new Date(s.starts_at).toLocaleTimeString('en-IN', { timeStyle: 'short' })}</div>
                <div className="flex items-center gap-2 mt-4">
                  {s.is_active
                    ? <span className="text-sm font-bold text-green-700 bg-green-100 border-2 border-green-400 px-3 py-1 rounded-lg">Active</span>
                    : <span className="text-sm text-zinc-400 font-medium">Ended</span>}
                  {s.attendance_locked && <span className="text-sm text-red-600 font-bold bg-red-50 border border-red-300 px-2 py-0.5 rounded">Locked</span>}
                  {!editable && !s.attendance_locked && <span className="text-sm text-zinc-400">Closed</span>}
                </div>
              </button>
            )
          })}
        </div>
      </div>
    )
  }

  // ── Main grid of all classes ──
  return (
    <div className="p-8 max-w-5xl mx-auto">
      <h1 className="text-3xl font-black text-zinc-900 mb-8">Attendance</h1>

      {assignments.length === 0 && (
        <div className="border-2 border-dashed border-zinc-300 rounded-xl py-16 text-center text-zinc-400">
          <Users size={40} className="mx-auto mb-4 opacity-40" />
          <p className="font-semibold text-lg">No classes assigned yet</p>
        </div>
      )}

      {Object.values(assignmentsBySubject).map((group: any) => (
        <div key={group.subject_code} className="mb-10">
          <div className="flex items-center gap-3 mb-4">
            <span className="bg-zinc-900 text-white text-sm font-black px-3 py-1.5 rounded-lg border-2 border-black">{group.subject_code}</span>
            <h2 className="font-black text-zinc-800 text-xl">{group.subject_name}</h2>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {group.items.map((a: any) => (
              <button key={a.id} onClick={() => setSelectedAssignment(a.id)}
                className="text-left bg-zinc-50 border-2 border-black rounded-xl p-5 shadow-[4px_4px_0_0_#000] hover:shadow-[2px_2px_0_0_#000] hover:translate-x-0.5 hover:translate-y-0.5 transition-all">
                <div className="font-bold text-zinc-900 text-lg">{a.division_label}</div>
                {a.batch_label && (
                  <span className="inline-block mt-2 bg-indigo-100 border-2 border-black text-indigo-900 text-sm font-bold px-3 py-1 rounded-lg">
                    Batch {a.batch_label}
                  </span>
                )}
                <div className="text-sm text-zinc-400 mt-3 font-medium capitalize">{a.subject_type === 'lab' ? 'Lab' : 'Lecture'}</div>
              </button>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}
