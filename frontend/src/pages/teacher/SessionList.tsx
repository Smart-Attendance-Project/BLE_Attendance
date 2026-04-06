import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useSearchParams, Link } from 'react-router-dom'
import { getMySessions, getAttendanceSummary, overrideAttendance, lockAttendance } from '../../api/endpoints'

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

  return (
    <div style={{ padding: 24 }}>
      <h2>Sessions</h2>
      <div style={{ display: 'flex', gap: 24 }}>
        {/* Session list */}
        <div style={{ minWidth: 280 }}>
          {sessions.length === 0 && <p>No sessions found.</p>}
          {sessions.map((s: any) => (
            <div key={s.id}
              onClick={() => setSelectedSession(s.id)}
              style={{ padding: 12, border: `1px solid ${selectedSession === s.id ? '#0070f3' : '#ddd'}`, borderRadius: 6, marginBottom: 8, cursor: 'pointer' }}>
              <strong>{s.subject}</strong>
              <div style={{ fontSize: 12, color: '#666' }}>{new Date(s.starts_at).toLocaleString('en-IN')}</div>
              <div style={{ fontSize: 12 }}>
                {s.is_active ? <span style={{ color: 'green' }}>● Active</span> : <span style={{ color: '#888' }}>Ended</span>}
                {s.attendance_locked && <span style={{ color: 'red', marginLeft: 8 }}>🔒 Locked</span>}
              </div>
            </div>
          ))}
        </div>

        {/* Attendance detail */}
        {selectedSession && summary && (
          <div style={{ flex: 1 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
              <h3 style={{ margin: 0 }}>{summary.subject} — {new Date(summary.starts_at).toLocaleDateString('en-IN')}</h3>
              <div style={{ display: 'flex', gap: 8 }}>
                <span>{summary.present_students}/{summary.total_students} present</span>
                {!summary.attendance_locked && (
                  <button onClick={() => lockMut.mutate()} style={{ background: '#e53e3e', color: '#fff', border: 'none', borderRadius: 4, padding: '4px 10px', cursor: 'pointer' }}>
                    Lock Attendance
                  </button>
                )}
              </div>
            </div>
            <div style={{ marginBottom: 8 }}>
              <input placeholder="Override reason (optional)" value={overrideReason}
                onChange={e => setOverrideReason(e.target.value)}
                style={{ padding: '4px 8px', width: 280, borderRadius: 4, border: '1px solid #ccc' }} />
            </div>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 14 }}>
              <thead>
                <tr style={{ background: '#f5f5f5' }}>
                  {['Student ID', 'Name', 'Detections', 'Ratio', 'Status', 'Bio', 'Toggle'].map(h => (
                    <th key={h} style={{ padding: '8px 10px', textAlign: 'left', borderBottom: '1px solid #ddd' }}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {summary.records.map((r: any) => (
                  <tr key={r.student_user_id} style={{ background: r.is_present ? '#f0fff4' : '#fff5f5' }}>
                    <td style={{ padding: '6px 10px' }}>{r.student_id}</td>
                    <td style={{ padding: '6px 10px' }}>{r.student_name}</td>
                    <td style={{ padding: '6px 10px' }}>{r.detection_count}</td>
                    <td style={{ padding: '6px 10px' }}>{(r.presence_ratio * 100).toFixed(0)}%</td>
                    <td style={{ padding: '6px 10px', fontWeight: 600, color: r.is_present ? 'green' : 'red' }}>
                      {r.is_present ? 'P' : 'A'}
                      {r.overridden_by_teacher && <span style={{ fontSize: 11, color: '#888', marginLeft: 4 }}>(override)</span>}
                    </td>
                    <td style={{ padding: '6px 10px' }}>{r.biometric_verified ? '✓' : '—'}</td>
                    <td style={{ padding: '6px 10px' }}>
                      <button
                        disabled={!!summary.attendance_locked}
                        onClick={() => overrideMut.mutate({ studentId: r.student_user_id, isPresent: !r.is_present })}
                        style={{ fontSize: 12, padding: '2px 8px', cursor: 'pointer' }}>
                        Mark {r.is_present ? 'Absent' : 'Present'}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
