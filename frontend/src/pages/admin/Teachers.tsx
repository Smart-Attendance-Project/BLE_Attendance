import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { adminListTeachers, adminCreateTeacher } from '../../api/endpoints'
import { UserPlus } from 'lucide-react'

export default function Teachers() {
  const qc = useQueryClient()
  const { data: teachers = [] } = useQuery({ queryKey: ['teachers'], queryFn: adminListTeachers })
  const [form, setForm] = useState({ full_name: '', teacher_id: '', password: 'Pass@123' })
  const [err, setErr] = useState('')

  const mut = useMutation({
    mutationFn: () => adminCreateTeacher(form),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['teachers'] }); setForm({ full_name: '', teacher_id: '', password: 'Pass@123' }); setErr('') },
    onError: (e: any) => setErr(e.response?.data?.detail || 'Error'),
  })

  return (
    <div className="p-6 max-w-3xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Teachers</h1>

      <div className="bg-white border border-gray-200 rounded-xl p-5 mb-6">
        <h3 className="font-semibold text-gray-800 mb-4 flex items-center gap-2"><UserPlus size={16} />Add Teacher</h3>
        <div className="flex gap-3 flex-wrap">
          <input placeholder="Full Name" value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))}
            className="flex-1 min-w-40 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          <input placeholder="Teacher ID (e.g. T022)" value={form.teacher_id} onChange={e => setForm(f => ({ ...f, teacher_id: e.target.value }))}
            className="w-36 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          <input placeholder="Password" value={form.password} onChange={e => setForm(f => ({ ...f, password: e.target.value }))}
            className="w-36 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          <button onClick={() => mut.mutate()} disabled={!form.full_name || !form.teacher_id}
            className="bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white text-sm font-medium px-4 py-2 rounded-lg transition-colors">
            Add
          </button>
        </div>
        {err && <p className="text-red-600 text-xs mt-2">{err}</p>}
      </div>

      <div className="bg-white border border-gray-200 rounded-xl overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-50 border-b border-gray-200">
              {['Teacher ID', 'Name'].map(h => (
                <th key={h} className="px-4 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {teachers.map((t: any) => (
              <tr key={t.id} className="hover:bg-gray-50">
                <td className="px-4 py-2.5 font-mono text-xs text-gray-600">{t.teacher_id}</td>
                <td className="px-4 py-2.5 font-medium text-gray-900">{t.full_name}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
