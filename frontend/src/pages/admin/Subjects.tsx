import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { listSubjects, createSubject } from '../../api/endpoints'
import { BookOpen } from 'lucide-react'

export default function Subjects() {
  const qc = useQueryClient()
  const { data: subjects = [] } = useQuery({ queryKey: ['subjects'], queryFn: listSubjects })
  const [form, setForm] = useState({ code: '', name: '', subject_type: 'lecture' })
  const [err, setErr] = useState('')

  const mut = useMutation({
    mutationFn: () => createSubject(form),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['subjects'] }); setForm({ code: '', name: '', subject_type: 'lecture' }); setErr('') },
    onError: (e: any) => setErr(e.response?.data?.detail || 'Error'),
  })

  return (
    <div className="p-6 max-w-3xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Subjects</h1>

      <div className="bg-white border border-gray-200 rounded-xl p-5 mb-6">
        <h3 className="font-semibold text-gray-800 mb-4 flex items-center gap-2"><BookOpen size={16} />Add Subject</h3>
        <div className="flex gap-3 flex-wrap">
          <input placeholder="Code (e.g. CEUC102)" value={form.code} onChange={e => setForm(f => ({ ...f, code: e.target.value }))}
            className="w-36 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          <input placeholder="Subject Name" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
            className="flex-1 min-w-48 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          <select value={form.subject_type} onChange={e => setForm(f => ({ ...f, subject_type: e.target.value }))}
            className="border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400">
            <option value="lecture">Lecture</option>
            <option value="lab">Lab</option>
          </select>
          <button onClick={() => mut.mutate()} disabled={!form.code || !form.name}
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
              {['Code', 'Name', 'Type'].map(h => (
                <th key={h} className="px-4 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {subjects.map((s: any) => (
              <tr key={s.id} className="hover:bg-gray-50">
                <td className="px-4 py-2.5 font-mono text-xs text-gray-600">{s.code}</td>
                <td className="px-4 py-2.5 font-medium text-gray-900">{s.name}</td>
                <td className="px-4 py-2.5">
                  <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${s.subject_type === 'lab' ? 'bg-orange-100 text-orange-700' : 'bg-blue-100 text-blue-700'}`}>
                    {s.subject_type}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
