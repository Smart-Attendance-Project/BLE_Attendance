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
    <div className="p-8 max-w-2xl mx-auto">
      <h1 className="text-3xl font-black text-zinc-900 mb-8">Export Attendance</h1>

      <div className="bg-zinc-50 border-2 border-black rounded-xl p-7 shadow-[6px_6px_0_0_#000] flex flex-col gap-6">
        <div>
          <label className="block text-base font-bold text-zinc-700 mb-2">Class / Subject</label>
          <select value={assignmentId} onChange={e => setAssignmentId(e.target.value)}
            className="w-full border-2 border-black rounded-lg px-4 py-3 text-base focus:outline-none focus:ring-2 focus:ring-indigo-400 shadow-[2px_2px_0_0_#000] bg-white">
            <option value="">Select a class</option>
            {assignments.map((a: any) => (
              <option key={a.id} value={a.id}>
                {a.subject_name} / {a.division_label}{a.batch_label ? ` / ${a.batch_label}` : ''}
              </option>
            ))}
          </select>
          {selected && (
            <p className="text-sm text-zinc-400 mt-1.5 font-mono">{selected.subject_code} / {selected.subject_type === 'lab' ? 'Lab' : 'Lecture'}</p>
          )}
        </div>

        <div>
          <label className="block text-base font-bold text-zinc-700 mb-2">Quick range</label>
          <div className="flex gap-3">
            {PRESETS.map(p => (
              <button key={p.label} onClick={() => { setFromDate(p.from); setToDate(p.to) }}
                className="px-4 py-2.5 rounded-lg text-base font-bold border-2 border-black bg-zinc-50 hover:bg-indigo-100 transition-colors shadow-[2px_2px_0_0_#000]">
                {p.label}
              </button>
            ))}
          </div>
        </div>

        <div className="flex gap-5">
          <div className="flex-1">
            <label className="block text-base font-bold text-zinc-700 mb-2">From</label>
            <input type="date" value={fromDate} onChange={e => setFromDate(e.target.value)}
              className="w-full border-2 border-black rounded-lg px-4 py-3 text-base focus:outline-none focus:ring-2 focus:ring-indigo-400 shadow-[2px_2px_0_0_#000] bg-white" />
          </div>
          <div className="flex-1">
            <label className="block text-base font-bold text-zinc-700 mb-2">To</label>
            <input type="date" value={toDate} onChange={e => setToDate(e.target.value)}
              className="w-full border-2 border-black rounded-lg px-4 py-3 text-base focus:outline-none focus:ring-2 focus:ring-indigo-400 shadow-[2px_2px_0_0_#000] bg-white" />
          </div>
        </div>

        {err && <p className="text-red-700 text-base bg-red-50 border-2 border-red-300 rounded-lg px-4 py-3 font-medium">{err}</p>}

        <button onClick={doExport} disabled={loading}
          className="flex items-center justify-center gap-3 bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 text-white font-black py-4 rounded-xl border-2 border-black shadow-[4px_4px_0_0_#000] hover:shadow-[2px_2px_0_0_#000] hover:translate-x-0.5 hover:translate-y-0.5 transition-all text-lg">
          <Download size={20} />{loading ? 'Exporting...' : 'Download Excel'}
        </button>
      </div>
    </div>
  )
}
