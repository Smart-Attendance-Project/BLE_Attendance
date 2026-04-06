import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { getMyDivisions, listBatches, getDivisionStudents, addStudent } from '../../api/endpoints'
import { UserPlus } from 'lucide-react'

export default function Students() {
  const qc = useQueryClient()
  const { data: divisions = [] } = useQuery({ queryKey: ['my-divisions'], queryFn: getMyDivisions })
  const [divId, setDivId] = useState<number | ''>('')
  const { data: batches = [] } = useQuery({ queryKey: ['batches', divId], queryFn: () => listBatches(divId as number), enabled: !!divId })
  const { data: students = [] } = useQuery({ queryKey: ['students', divId], queryFn: () => getDivisionStudents(divId as number), enabled: !!divId })
  const [form, setForm] = useState({ full_name: '', student_id: '', batch_id: '' })
  const [err, setErr] = useState('')
  const [showForm, setShowForm] = useState(false)

  const addMut = useMutation({
    mutationFn: () => addStudent({ full_name: form.full_name, student_id: form.student_id, division_id: divId as number, batch_id: form.batch_id ? Number(form.batch_id) : undefined }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['students', divId] }); setForm({ full_name: '', student_id: '', batch_id: '' }); setErr(''); setShowForm(false) },
    onError: (e: any) => setErr(e.response?.data?.detail || 'Error adding student'),
  })

  const inp = "border-2 border-black rounded-lg px-4 py-3 text-base focus:outline-none focus:ring-2 focus:ring-indigo-400 shadow-[2px_2px_0_0_#000] bg-white"

  return (
    <div className="p-8 max-w-4xl mx-auto">
      <h1 className="text-3xl font-black text-zinc-900 mb-8">Students</h1>

      <div className="flex items-center gap-4 mb-6">
        <select value={divId} onChange={e => { setDivId(Number(e.target.value)); setShowForm(false) }}
          className={`${inp} min-w-56`}>
          <option value="">Select division</option>
          {divisions.map((d: any) => <option key={d.id} value={d.id}>{d.label}</option>)}
        </select>
        {divId && (
          <button onClick={() => setShowForm(v => !v)}
            className="flex items-center gap-2 bg-zinc-900 hover:bg-zinc-800 text-white text-base font-bold px-5 py-3 rounded-lg border-2 border-black shadow-[3px_3px_0_0_#000] hover:shadow-[1px_1px_0_0_#000] hover:translate-x-0.5 hover:translate-y-0.5 transition-all">
            <UserPlus size={17} /> Add Student
          </button>
        )}
      </div>

      {showForm && divId && (
        <div className="bg-zinc-50 border-2 border-black rounded-xl p-6 mb-6 shadow-[4px_4px_0_0_#000]">
          <h3 className="font-black text-zinc-800 text-lg mb-4">Add Student</h3>
          <div className="flex flex-col gap-4">
            <div className="flex gap-4">
              <input placeholder="Full Name" value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))} className={`${inp} flex-1`} />
              <input placeholder="Student ID (e.g. 25CE099)" value={form.student_id} onChange={e => setForm(f => ({ ...f, student_id: e.target.value }))} className={`${inp} flex-1`} />
            </div>
            <div className="flex gap-4 items-end">
              <select value={form.batch_id} onChange={e => setForm(f => ({ ...f, batch_id: e.target.value }))} className={`${inp} min-w-48`}>
                <option value="">No batch (lecture only)</option>
                {batches.map((b: any) => <option key={b.id} value={b.id}>{b.label}</option>)}
              </select>
              {err && <p className="text-red-600 text-sm font-medium">{err}</p>}
              <button onClick={() => addMut.mutate()} disabled={!form.full_name || !form.student_id}
                className="bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 text-white text-base font-bold px-6 py-3 rounded-lg border-2 border-black shadow-[3px_3px_0_0_#000] transition-all">
                Add
              </button>
            </div>
          </div>
        </div>
      )}

      {divId && (
        <div className="bg-zinc-50 border-2 border-black rounded-xl overflow-hidden shadow-[4px_4px_0_0_#000]">
          <table className="w-full text-base">
            <thead>
              <tr className="bg-zinc-900 text-white">
                {['Student ID', 'Name', 'Batch'].map(h => (
                  <th key={h} className="px-5 py-4 text-left text-sm font-bold uppercase tracking-wider">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-200">
              {students.length === 0 && (
                <tr><td colSpan={3} className="px-5 py-10 text-center text-zinc-400 text-base">No students in this division</td></tr>
              )}
              {students.map((s: any) => (
                <tr key={s.id} className="hover:bg-zinc-100">
                  <td className="px-5 py-3.5 font-mono text-sm text-zinc-500">{s.student_id}</td>
                  <td className="px-5 py-3.5 font-semibold text-zinc-900">{s.full_name}</td>
                  <td className="px-5 py-3.5">
                    {s.batch_id
                      ? <span className="bg-indigo-100 border border-black text-indigo-900 text-sm font-bold px-3 py-1 rounded-lg">{batches.find((b: any) => b.id === s.batch_id)?.label || 'Unknown'}</span>
                      : <span className="text-zinc-400">No batch</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
