import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useSearchParams } from 'react-router-dom'
import { getMySessions, getMyAssignments, getAttendanceSummary, overrideAttendance } from '../../api/endpoints'
import { CheckCircle, XCircle, AlertCircle, ChevronLeft, Users, BookOpen } from 'lucide-react'

// A session is editable if it ended less than 24h ago (or is still active)
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

  // Group assignments by subject for display
  const assignmentsBySubject = assignments.reduce((acc: any, a: any) => {
    const key = a.subject_code
    if (!acc[key]) acc[key] = { subject_name: a.subject_name, subject_code: a.subject_code, items: [] }
    acc[key].items.push(a)
    return acc
  }, {})

  if (selectedSession && summary) {
    return (
      <div className="p-6 max-w-5xl mx-auto">
        <button onClick={() => setSelectedSession(null)}
          className="flex items-center gap-1.5 text-sm text-zinc-500 hover:text-zinc-900 mb-5 transition-colors">
          <ChevronLeft size={16} /> Back to sessions
        </button>

        <div className="bg-zinc-50 border-2 border-black rounded-xl p-4 mb-5 shadow-[4px_4px_0_0_#000] flex items-center justify-between gap-4 flex-wrap">
          <div>
            <h2 className="font-black text-zinc-900 text-lg">{summary.subject}</h2>
            <p className="text-sm text-zinc-500">{new Date(summary.starts_at).toLocaleDateString('en-IN', { dateStyle: 'full' })}</p>
          </div>
          <div className="flex items-center gap-4">
            <div className="text-center">
              <div className="text-3xl font-black text-zinc-900">{summary.present_students}<span className="text-zinc-400 font-normal text-lg">/{summary.total_students}</span></div>
              <div className="text-xs text-zinc-500 font-medium">Present</div>
            </div>
            {!editable && (
              <span className="bg-zinc-100 border border-zinc-300 text-zinc-500 text-xs font-semibold px-3 py-1.5 rounded-lg">
                {selectedSessionData?.attendance_locked ? '🔒 Locked' : '⏱ Editing closed (>24h)'}
              </span>
            )}
          </div>
        </div>

        {editable && (
          <div className="mb-4">
            <input placeholder="Override reason (optional)"
              value={overrideReason} onChange={e => setOverrideReason(e.target.value)}
              className="border-2 border-black rounded-lg px-3 py-2 text-sm w-72 focus:outline-none focus:ring-2 focus:ring-indigo-400 shadow-[2px_2px_0_0_#000]" />
          </div>
        )}

        <div className="bg-zinc-50 border-2 border-black rounded-xl overflow-hidden shadow-[4px_4px_0_0_#000]">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-zinc-900 text-white">
                {['Student ID', 'Name', 'Detections', 'Ratio', 'Status', 'Bio', ''].map(h => (
                  <th key={h} className="px-4 py-3 text-left text-xs font-bold uppercase tracking-wider">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-100">
              {summary.records.map((r: any) => (
                <tr key={r.student_user_id} className={r.is_present ? 'bg-green-50' : 'bg-red-50/50'}>
                  <td className="px-4 py-2.5 font-mono text-xs text-zinc-500">{r.student_id}</td>
                  <td className="px-4 py-2.5 font-semibold text-zinc-900">{r.student_name}</td>
                  <td className="px-4 py-2.5 text-zinc-600">{r.detection_count}</td>
                  <td className="px-4 py-2.5 text-zinc-600">{(r.presence_ratio * 100).toFixed(0)}%</td>
                  <td className="px-4 py-2.5">
                    <span className={`inline-flex items-center gap-1 text-xs font-bold px-2 py-0.5 rounded border ${r.is_present ? 'bg-green-100 text-green-800 border-green-300' : 'bg-red-100 text-red-800 border-red-300'}`}>
                      {r.is_present ? <CheckCircle size={11} /> : <XCircle size={11} />}
                      {r.is_present ? 'P' : 'A'}
                      {r.overridden_by_teacher && <AlertCircle size={10} className="opacity-60" />}
                    </span>
                  </td>
                  <td className="px-4 py-2.5 text-zinc-500">{r.biometric_verified ? '✓' : '—'}</td>
                  <td className="px-4 py-2.5">
                    <button
                      disabled={!editable}
                      onClick={() => overrideMut.mutate({ studentId: r.student_user_id, isPresent: !r.is_present })}
                      className="text-xs px-2.5 py-1 rounded border-2 border-black font-semibold bg-white hover:bg-indigo-100 disabled:opacity-30 disabled:cursor-not-allowed disabled:hover:bg-white transition-colors shadow-[1px_1px_0_0_#000] disabled:shadow-none">
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

  if (selectedAssignment && !selectedSession) {
    const assignment = assignments.find((a: any) => a.id === selectedAssignment)
    return (
      <div className="p-6 max-w-4xl mx-auto">
        <button onClick={() => setSelectedAssignment(null)}
          className="flex items-center gap-1.5 text-sm text-zinc-500 hover:text-zinc-900 mb-5 transition-colors">
          <ChevronLeft size={16} /> Back to classes
        </button>

        <div className="mb-5">
          <h1 className="text-2xl font-black text-zinc-900">{assignment?.subject_name}</h1>
          <p className="text-zinc-500 text-sm">{assignment?.division_label}{assignment?.batch_label ? ` · Batch ${assignment.batch_label}` : ''}</p>
        </div>

        {sessions.length === 0 && (
          <div className="border-2 border-dashed border-zinc-300 rounded-xl py-12 text-center text-zinc-400">
            <BookOpen size={32} className="mx-auto mb-3 opacity-40" />
            <p className="font-semibold">No sessions recorded yet for this class</p>
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {sessions.map((s: any) => {
            const editable = isEditable(s)
            return (
              <button key={s.id} onClick={() => setSelectedSession(s.id)}
                className="text-left bg-white border-2 border-black rounded-xl p-4 shadow-[4px_4px_0_0_#000] hover:shadow-[2px_2px_0_0_#000] hover:translate-x-0.5 hover:translate-y-0.5 transition-all">
                <div className="font-black text-zinc-900">{new Date(s.starts_at).toLocaleDateString('en-IN', { dateStyle: 'medium' })}</div>
                <div className="text-xs text-zinc-500 mt-0.5">{new Date(s.starts_at).toLocaleTimeString('en-IN', { timeStyle: 'short' })}</div>
                <div className="flex items-center gap-2 mt-3">
                  {s.is_active
                    ? <span className="text-xs font-bold text-green-700 bg-green-100 border border-green-300 px-2 py-0.5 rounded">● Active</span>
                    : <span className="text-xs text-zinc-400">Ended</span>}
                  {s.attendance_locked && <span className="text-xs text-red-600 font-bold">🔒</span>}
                  {!editable && !s.attendance_locked && <span className="text-xs text-zinc-400">⏱ Closed</span>}
                </div>
              </button>
            )
          })}
        </div>
      </div>
    )
  }

  // Main grid — all assignments grouped by subject
  return (
    <div className="p-6 max-w-5xl mx-auto">
      <h1 className="text-2xl font-black text-zinc-900 mb-6">Attendance</h1>

      {assignments.length === 0 && (
        <div className="border-2 border-dashed border-zinc-300 rounded-xl py-12 text-center text-zinc-400">
          <Users size={32} className="mx-auto mb-3 opacity-40" />
          <p className="font-semibold">No classes assigned yet</p>
        </div>
      )}

      {Object.values(assignmentsBySubject).map((group: any) => (
        <div key={group.subject_code} className="mb-8">
          <div className="flex items-center gap-3 mb-3">
            <span className="bg-zinc-900 text-white text-xs font-black px-2.5 py-1 rounded border border-black">{group.subject_code}</span>
            <h2 className="font-black text-zinc-800">{group.subject_name}</h2>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {group.items.map((a: any) => (
              <button key={a.id} onClick={() => setSelectedAssignment(a.id)}
                className="text-left bg-white border-2 border-black rounded-xl p-4 shadow-[4px_4px_0_0_#000] hover:shadow-[2px_2px_0_0_#000] hover:translate-x-0.5 hover:translate-y-0.5 transition-all">
                <div className="font-bold text-zinc-900">{a.division_label}</div>
                {a.batch_label && (
                  <span className="inline-block mt-1 bg-indigo-100 border border-black text-black text-xs font-bold px-2 py-0.5 rounded">
                    Batch {a.batch_label}
                  </span>
                )}
                <div className="text-xs text-zinc-400 mt-2 capitalize">{a.subject_type === 'lab' ? '🔬 Lab' : '📖 Lecture'}</div>
              </button>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}
