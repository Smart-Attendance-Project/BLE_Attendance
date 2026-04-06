import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { getMyAssignments, exportAttendance } from '../../api/endpoints'

export default function Export() {
  const { data: assignments = [] } = useQuery({ queryKey: ['my-assignments'], queryFn: getMyAssignments })
  const [assignmentId, setAssignmentId] = useState('')
  const [fromDate, setFromDate] = useState('')
  const [toDate, setToDate] = useState('')
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState('')

  const today = new Date().toISOString().split('T')[0]

  const presets = [
    { label: 'Today', from: today, to: today },
    { label: 'This Week', from: getMondayOfWeek(), to: today },
    { label: 'This Month', from: getMonthStart(), to: today },
  ]

  const doExport = async () => {
    if (!assignmentId || !fromDate || !toDate) { setErr('Fill all fields'); return }
    setErr('')
    setLoading(true)
    try {
      const res = await exportAttendance(Number(assignmentId), fromDate, toDate)
      const url = URL.createObjectURL(res.data)
      const a = document.createElement('a')
      a.href = url
      a.download = `attendance_${fromDate}_to_${toDate}.xlsx`
      a.click()
      URL.revokeObjectURL(url)
    } catch {
      setErr('Export failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{ padding: 24, maxWidth: 600 }}>
      <h2>Export Attendance</h2>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div>
          <label>Class / Subject</label>
          <select value={assignmentId} onChange={e => setAssignmentId(e.target.value)} style={{ display: 'block', width: '100%', padding: 8, marginTop: 4 }}>
            <option value="">— Select —</option>
            {assignments.map((a: any) => (
              <option key={a.id} value={a.id}>
                {a.subject_name} · {a.division_label}{a.batch_label ? ` · ${a.batch_label}` : ''}
              </option>
            ))}
          </select>
        </div>

        <div style={{ display: 'flex', gap: 8 }}>
          {presets.map(p => (
            <button key={p.label} onClick={() => { setFromDate(p.from); setToDate(p.to) }}
              style={{ padding: '4px 12px', cursor: 'pointer', background: fromDate === p.from && toDate === p.to ? '#0070f3' : '#eee', color: fromDate === p.from && toDate === p.to ? '#fff' : '#333', border: 'none', borderRadius: 4 }}>
              {p.label}
            </button>
          ))}
        </div>

        <div style={{ display: 'flex', gap: 12 }}>
          <div style={{ flex: 1 }}>
            <label>From</label>
            <input type="date" value={fromDate} onChange={e => setFromDate(e.target.value)} style={{ display: 'block', width: '100%', padding: 8, marginTop: 4 }} />
          </div>
          <div style={{ flex: 1 }}>
            <label>To</label>
            <input type="date" value={toDate} onChange={e => setToDate(e.target.value)} style={{ display: 'block', width: '100%', padding: 8, marginTop: 4 }} />
          </div>
        </div>

        {err && <span style={{ color: 'red' }}>{err}</span>}
        <button onClick={doExport} disabled={loading} style={{ padding: '10px 20px', background: '#0070f3', color: '#fff', border: 'none', borderRadius: 6, cursor: 'pointer', fontSize: 15 }}>
          {loading ? 'Exporting…' : '⬇ Download Excel'}
        </button>
      </div>
    </div>
  )
}

function getMondayOfWeek() {
  const d = new Date()
  const day = d.getDay()
  const diff = d.getDate() - day + (day === 0 ? -6 : 1)
  return new Date(d.setDate(diff)).toISOString().split('T')[0]
}

function getMonthStart() {
  const d = new Date()
  return new Date(d.getFullYear(), d.getMonth(), 1).toISOString().split('T')[0]
}
