import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { getMyAssignments, exportAttendance } from '../../api/endpoints'
import { Download, Calendar } from 'lucide-react'

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
    if (!assignmentId || !fromDate || !toDate) { setErr('Please fill all fields'); return }
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
      setErr('Export failed. No sessions may exist for this range.')
    } finally {
      setLoading(false)
    }
  }

  const selected = assignments.find((a: any) => String(a.id) === assignmentId)

  return (
    <div className="p-6 max-w-2xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Export Attendance</h1>

      <div className="bg-white border border-gray-200 rounded-xl p-6 flex flex-col gap-5">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1.5">Class / Subject</label>
          <select value={assignmentId} onChange={e => setAssignmentId(e.target.value)}
            className="w-full border border-gray-300 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400">
            <option value="">— Select a class —</option>
            {assignments.map((a: any) => (
              <option key={a.id} value={a.id}>
                {a.subject_name} · {a.division_label}{a.batch_label ? ` · Batch ${a.batch_label}` : ''}
              </option>
            ))}
          </select>
          {selected && (
            <p className="text-xs text-gray-500 mt-1.5 font-mono">{selected.subject_code} · {selected.subject_type === 'lab' ? 'Lab' : 'Lecture'}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-2">Quick select</label>
          <div className="flex gap-2">
            {presets.map(p => {
              const active = fromDate === p.from && toDate === p.to
              return (
                <button key={p.label} onClick={() => { setFromDate(p.from); setToDate(p.to) }}
                  className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium border transition-colors ${active ? 'bg-indigo-600 text-white border-indigo-600' : 'bg-white text-gray-600 border-gray-300 hover:border-indigo-300'}`}>
                  <Calendar size={13} />{p.label}
                </button>
              )
            })}
          </div>
        </div>

        <div className="flex gap-4">
          <div className="flex-1">
            <label className="block text-sm font-medium text-gray-700 mb-1.5">From</label>
            <input type="date" value={fromDate} onChange={e => setFromDate(e.target.value)}
              className="w-full border border-gray-300 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          </div>
          <div className="flex-1">
            <label className="block text-sm font-medium text-gray-700 mb-1.5">To</label>
            <input type="date" value={toDate} onChange={e => setToDate(e.target.value)}
              className="w-full border border-gray-300 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          </div>
        </div>

        {err && <p className="text-red-600 text-sm bg-red-50 border border-red-200 rounded-lg px-3 py-2">{err}</p>}

        <button onClick={doExport} disabled={loading}
          className="flex items-center justify-center gap-2 bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white font-semibold py-3 rounded-xl transition-colors">
          <Download size={18} />{loading ? 'Exporting…' : 'Download Excel'}
        </button>
      </div>
    </div>
  )
}

function getMondayOfWeek() {
  const d = new Date()
  const day = d.getDay()
  const diff = d.getDate() - day + (day === 0 ? -6 : 1)
  return new Date(new Date().setDate(diff)).toISOString().split('T')[0]
}

function getMonthStart() {
  const d = new Date()
  return new Date(d.getFullYear(), d.getMonth(), 1).toISOString().split('T')[0]
}
