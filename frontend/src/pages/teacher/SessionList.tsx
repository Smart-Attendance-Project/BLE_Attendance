import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useSearchParams } from 'react-router-dom'
import { getMySessions, getAttendanceSummary, overrideAttendance, lockAttendance } from '../../api/endpoints'
import { Lock, CheckCircle, XCircle, AlertCircle } from 'lucide-react'

export default function SessionList() {
  const [params] = useSearchParams()
  const assignmentId = params.get('assignment_id')
  const [selectedSession, setSelectedSession] = useState<string | null>(null)
  const [overrideReason, setOverrideReason] = useState('')
  const qc = useQueryClient()

  const { data: sessions = [] } = useQuery({
    queryKey: ['sessions', assignmentId],
    queryFn: () => getMySessions(assignmentId ? { assignment_id: assignmentId } : undefined),
  })

  const { data: summary } = useQuery({
    queryKey: ['summary', selectedSession],
    queryFn: () => getAttendanceSummary(selectedSession!),
    enabled: !!selectedSession,
  })

  const overrideMut = useMutation({
    mutationFn: ({ studentId, isPresent }: { studentId: string; isPresent: boolean }) =>
      overrideAttendance(selectedSession!, { student_user_id: studentId, is_present: isPresent, reason: overrideReason || 'Manual override' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['summary', selectedSession] }),
  })

  const lockMut = useMutation({
    mutationFn: () => lockAttendance(selectedSession!),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['summary', selectedSession] }),
  })

  const selectedSessionData = sessions.find((s: any) => s.id === selectedSession)

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Attendance</h1>
      <div className="flex gap-5">
        {/* Session list */}
        <div className="w-72 shrink-0 flex flex-col gap-2">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-1">Sessions</p>
          {sessions.length === 0 && <p className="text-sm text-gray-400 py-4 text-center">No sessions found</p>}
          {sessions.map((s: any) => (
            <button key={s.id} onClick={() => setSelectedSession(s.id)}
              className={`text-left p-3 rounded-xl border transition-all ${selectedSession === s.id ? 'border-indigo-400 bg-indigo-50 shadow-sm' : 'border-gray-200 bg-white hover:border-gray-300'}`}>
              <div className="font-medium text-sm text-gray-900 truncate">{s.subject}</div>
              <div className="text-xs text-gray-500 mt-0.5">{new Date(s.starts_at).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' })}</div>
              <div className="flex items-center gap-2 mt-1.5">
                {s.is_active
                  ? <span className="text-xs text-green-600 font-medium flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-green-500 inline-block" />Active</span>
                  : <span className="text-xs text-gray-400">Ended</span>}
                {s.attendance_locked && <span className="text-xs text-red-500 flex items-center gap-1"><Lock size={10} />Locked</span>}
              </div>
            </button>
          ))}
        </div>

        {/* Attendance detail */}
        {selectedSession && summary ? (
          <div className="flex-1 min-w-0">
            <div className="bg-white border border-gray-200 rounded-xl p-4 mb-4 flex items-center justify-between gap-4">
              <div>
                <h2 className="font-semibold text-gray-900">{summary.subject}</h2>
                <p className="text-sm text-gray-500">{new Date(summary.starts_at).toLocaleDateString('en-IN', { dateStyle: 'full' })}</p>
              </div>
              <div className="flex items-center gap-3">
                <div className="text-center">
                  <div className="text-2xl font-bold text-indigo-600">{summary.present_students}<span className="text-gray-400 font-normal text-base">/{summary.total_students}</span></div>
                  <div className="text-xs text-gray-500">Present</div>
                </div>
                {!selectedSessionData?.attendance_locked && (
                  <button onClick={() => lockMut.mutate()}
                    className="flex items-center gap-1.5 bg-red-50 hover:bg-red-100 text-red-600 border border-red-200 text-sm font-medium px-3 py-2 rounded-lg transition-colors">
                    <Lock size={14} /> Lock
                  </button>
                )}
                {selectedSessionData?.attendance_locked && (
                  <span className="flex items-center gap-1.5 text-red-500 text-sm font-medium"><Lock size={14} /> Locked</span>
                )}
              </div>
            </div>

            <div className="mb-3">
              <input placeholder="Override reason (optional)"
                value={overrideReason} onChange={e => setOverrideReason(e.target.value)}
                className="border border-gray-300 rounded-lg px-3 py-2 text-sm w-72 focus:outline-none focus:ring-2 focus:ring-indigo-400" />
            </div>

            <div className="bg-white border border-gray-200 rounded-xl overflow-hidden">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-200">
                    {['Student ID', 'Name', 'Detections', 'Ratio', 'Status', 'Bio', ''].map(h => (
                      <th key={h} className="px-4 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {summary.records.map((r: any) => (
                    <tr key={r.student_user_id} className={r.is_present ? 'bg-green-50/40' : 'bg-red-50/30'}>
                      <td className="px-4 py-2.5 font-mono text-xs text-gray-600">{r.student_id}</td>
                      <td className="px-4 py-2.5 font-medium text-gray-900">{r.student_name}</td>
                      <td className="px-4 py-2.5 text-gray-600">{r.detection_count}</td>
                      <td className="px-4 py-2.5 text-gray-600">{(r.presence_ratio * 100).toFixed(0)}%</td>
                      <td className="px-4 py-2.5">
                        <span className={`inline-flex items-center gap-1 text-xs font-semibold px-2 py-0.5 rounded-full ${r.is_present ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
                          {r.is_present ? <CheckCircle size={11} /> : <XCircle size={11} />}
                          {r.is_present ? 'P' : 'A'}
                          {r.overridden_by_teacher && <AlertCircle size={10} className="opacity-60" />}
                        </span>
                      </td>
                      <td className="px-4 py-2.5 text-gray-500">{r.biometric_verified ? '✓' : '—'}</td>
                      <td className="px-4 py-2.5">
                        <button
                          disabled={!!selectedSessionData?.attendance_locked}
                          onClick={() => overrideMut.mutate({ studentId: r.student_user_id, isPresent: !r.is_present })}
                          className="text-xs px-2.5 py-1 rounded-lg border border-gray-300 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed transition-colors">
                          Mark {r.is_present ? 'Absent' : 'Present'}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        ) : (
          <div className="flex-1 flex items-center justify-center text-gray-400">
            <div className="text-center">
              <CheckCircle size={40} className="mx-auto mb-3 opacity-30" />
              <p>Select a session to view attendance</p>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
