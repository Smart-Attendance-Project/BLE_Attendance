import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { adminListTeachers, adminCreateTeacher } from '../../api/endpoints'

const inp = "border-2 border-black rounded-lg px-4 py-3 text-base focus:outline-none focus:ring-2 focus:ring-indigo-400 shadow-[2px_2px_0_0_#000] bg-white"

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
    <div className="p-8 max-w-4xl mx-auto">
      <h1 className="text-3xl font-black text-zinc-900 mb-8">Teachers</h1>

      <div className="bg-zinc-50 border-2 border-black rounded-xl p-6 mb-8 shadow-[4px_4px_0_0_#000]">
        <h3 className="font-black text-zinc-800 text-lg mb-4">Add Teacher</h3>
        <div className="flex gap-4 flex-wrap">
          <input placeholder="Full Name" value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))} className={`${inp} flex-1 min-w-48`} />
          <input placeholder="Teacher ID (e.g. T023)" value={form.teacher_id} onChange={e => setForm(f => ({ ...f, teacher_id: e.target.value }))} className={`${inp} w-40`} />
          <input placeholder="Password" value={form.password} onChange={e => setForm(f => ({ ...f, password: e.target.value }))} className={`${inp} w-40`} />
          <button onClick={() => mut.mutate()} disabled={!form.full_name || !form.teacher_id}
            className="bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 text-white text-base font-bold px-6 py-3 rounded-lg border-2 border-black shadow-[3px_3px_0_0_#000] transition-all">
            Add
          </button>
        </div>
        {err && <p className="text-red-600 text-sm font-medium mt-3">{err}</p>}
      </div>

      <div className="bg-zinc-50 border-2 border-black rounded-xl overflow-hidden shadow-[4px_4px_0_0_#000]">
        <table className="w-full text-base">
          <thead>
            <tr className="bg-zinc-900 text-white">
              {['Teacher ID', 'Name'].map(h => (
                <th key={h} className="px-5 py-4 text-left text-sm font-bold uppercase tracking-wider">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-200">
            {teachers.map((t: any) => (
              <tr key={t.id} className="hover:bg-zinc-100">
                <td className="px-5 py-3.5 font-mono text-sm text-zinc-500">{t.teacher_id}</td>
                <td className="px-5 py-3.5 font-semibold text-zinc-900">{t.full_name}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
