import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { getMyAssignments, exportAttendance } from '../../api/endpoints'
import { Download } from 'lucide-react'

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

const today = new Date().toISOString().split('T')[0]

const PRESETS = [
  { label: 'This Week', from: getMondayOfWeek(), to: today },
  { label: 'This Month', from: getMonthStart(), to: today },
]

export default function Export() {
  const { data: assignments = [] } = useQuery({ queryKey: ['my-assignments'], queryFn: getMyAssignments })
  const [assignmentId, setAssignmentId] = useState('')
  const [fromDate, setFromDate] = useState(today)
  const [toDate, setToDate] = useState(today)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState('')

  const doExport = async () => {
    if (!assignmentId) { setErr('Select a class first'); return }
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
      setErr('Export failed — no sessions may exist for this range.')
    } finally {
      setLoading(false)
    }
  }

  const selected = assignments.find((a: any) => String(a.id) === assignmentId)

  return (
    <div className="p-6 max-w-xl mx-auto">
      <h1 className="text-2xl font-black text-zinc-900 mb-6">Export Attendance</h1>

      <div className="bg-white border-2 border-black rounded-xl p-6 shadow-[6px_6px_0_0_#000] flex flex-col gap-5">
        <div>
          <label className="block text-sm font-bold text-zinc-700 mb-1.5">Class / Subject</label>
          <select value={assignmentId} onChange={e => setAssignmentId(e.target.value)}
            className="w-full border-2 border-black rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-yellow-400 shadow-[2px_2px_0_0_#000]">
            <option value="">— Select a class —</option>
            {assignments.map((a: any) => (
              <option key={a.id} value={a.id}>
                {a.subject_name} · {a.division_label}{a.batch_label ? ` · ${a.batch_label}` : ''}
              </option>
            ))}
          </select>
          {selected && (
            <p className="text-xs text-zinc-400 mt-1 font-mono">{selected.subject_code} · {selected.subject_type === 'lab' ? 'Lab' : 'Lecture'}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-bold text-zinc-700 mb-2">Quick range</label>
          <div className="flex gap-2">
            {PRESETS.map(p => (
              <button key={p.label} onClick={() => { setFromDate(p.from); setToDate(p.to) }}
                className="px-3 py-1.5 rounded-lg text-sm font-bold border-2 border-black bg-white hover:bg-yellow-400 transition-colors shadow-[2px_2px_0_0_#000]">
                {p.label}
              </button>
            ))}
          </div>
        </div>

        <div className="flex gap-4">
          <div className="flex-1">
            <label className="block text-sm font-bold text-zinc-700 mb-1.5">From</label>
            <input type="date" value={fromDate} onChange={e => setFromDate(e.target.value)}
              className="w-full border-2 border-black rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-yellow-400 shadow-[2px_2px_0_0_#000]" />
          </div>
          <div className="flex-1">
            <label className="block text-sm font-bold text-zinc-700 mb-1.5">To</label>
            <input type="date" value={toDate} onChange={e => setToDate(e.target.value)}
              className="w-full border-2 border-black rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-yellow-400 shadow-[2px_2px_0_0_#000]" />
          </div>
        </div>

        {err && <p className="text-red-700 text-sm bg-red-50 border-2 border-red-300 rounded-lg px-3 py-2 font-medium">{err}</p>}

        <button onClick={doExport} disabled={loading}
          className="flex items-center justify-center gap-2 bg-yellow-400 hover:bg-yellow-300 disabled:opacity-50 text-black font-black py-3 rounded-xl border-2 border-black shadow-[4px_4px_0_0_#000] hover:shadow-[2px_2px_0_0_#000] hover:translate-x-0.5 hover:translate-y-0.5 transition-all">
          <Download size={18} />{loading ? 'Exporting…' : 'Download Excel'}
        </button>
      </div>
    </div>
  )
}
