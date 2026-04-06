import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { getMyDivisions, listBatches, getDivisionStudents, addStudent } from '../../api/endpoints'
import { UserPlus } from 'lucide-react'

export default function Students() {
  const qc = useQueryClient()
  // Only show divisions this teacher is assigned to
  const { data: divisions = [] } = useQuery({ queryKey: ['my-divisions'], queryFn: getMyDivisions })
  const [divId, setDivId] = useState<number | ''>('')
  const { data: batches = [] } = useQuery({ queryKey: ['batches', divId], queryFn: () => listBatches(divId as number), enabled: !!divId })
  const { data: students = [] } = useQuery({ queryKey: ['students', divId], queryFn: () => getDivisionStudents(divId as number), enabled: !!divId })

  const [form, setForm] = useState({ full_name: '', student_id: '', batch_id: '' })
  const [err, setErr] = useState('')
  const [showForm, setShowForm] = useState(false)

  const addMut = useMutation({
    mutationFn: () => addStudent({
      full_name: form.full_name, student_id: form.student_id,
      division_id: divId as number,
      batch_id: form.batch_id ? Number(form.batch_id) : undefined,
    }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['students', divId] })
      setForm({ full_name: '', student_id: '', batch_id: '' })
      setErr('')
      setShowForm(false)
    },
    onError: (e: any) => setErr(e.response?.data?.detail || 'Error adding student'),
  })

  return (
    <div className="p-6 max-w-3xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Students</h1>

      <div className="flex items-center gap-3 mb-5">
        <select value={divId} onChange={e => { setDivId(Number(e.target.value)); setShowForm(false) }}
          className="border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400">
          <option value="">— Select division —</option>
          {divisions.map((d: any) => <option key={d.id} value={d.id}>{d.label}</option>)}
        </select>
        {divId && (
          <button onClick={() => setShowForm(v => !v)}
            className="flex items-center gap-1.5 bg-indigo-600 hover:bg-indigo-700 text-white text-sm font-medium px-3 py-2 rounded-lg transition-colors">
            <UserPlus size={15} /> Add Student
          </button>
        )}
      </div>

      {showForm && divId && (
        <div className="bg-white border border-gray-200 rounded-xl p-4 mb-5">
          <h3 className="font-semibold text-gray-800 mb-3">Add Student</h3>
          <div className="flex flex-col gap-3">
            <div className="flex gap-3">
              <input placeholder="Full Name" value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))}
                className="flex-1 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
              <input placeholder="Student ID (e.g. 25CE099)" value={form.student_id} onChange={e => setForm(f => ({ ...f, student_id: e.target.value }))}
                className="flex-1 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
            </div>
            <div className="flex gap-3 items-end">
              <select value={form.batch_id} onChange={e => setForm(f => ({ ...f, batch_id: e.target.value }))}
                className="border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400">
                <option value="">No batch (lecture only)</option>
                {batches.map((b: any) => <option key={b.id} value={b.id}>{b.label}</option>)}
              </select>
              {err && <p className="text-red-600 text-xs">{err}</p>}
              <button onClick={() => addMut.mutate()} disabled={!form.full_name || !form.student_id}
                className="bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white text-sm font-medium px-4 py-2 rounded-lg transition-colors">
                Add
              </button>
            </div>
          </div>
        </div>
      )}

      {divId && (
        <div className="bg-white border border-gray-200 rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b border-gray-200">
                {['Student ID', 'Name', 'Batch'].map(h => (
                  <th key={h} className="px-4 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {students.length === 0 && (
                <tr><td colSpan={3} className="px-4 py-8 text-center text-gray-400 text-sm">No students in this division</td></tr>
              )}
              {students.map((s: any) => (
                <tr key={s.id} className="hover:bg-gray-50">
                  <td className="px-4 py-2.5 font-mono text-xs text-gray-600">{s.student_id}</td>
                  <td className="px-4 py-2.5 font-medium text-gray-900">{s.full_name}</td>
                  <td className="px-4 py-2.5">
                    {s.batch_id
                      ? <span className="bg-indigo-50 text-indigo-700 text-xs font-medium px-2 py-0.5 rounded-full">{batches.find((b: any) => b.id === s.batch_id)?.label || '—'}</span>
                      : <span className="text-gray-400">—</span>}
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
