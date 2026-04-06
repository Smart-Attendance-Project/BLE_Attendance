import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { listSubjects, createSubject } from '../../api/endpoints'

const inp = "border-2 border-black rounded-lg px-4 py-3 text-base focus:outline-none focus:ring-2 focus:ring-indigo-400 shadow-[2px_2px_0_0_#000] bg-white"

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
    <div className="p-8 max-w-4xl mx-auto">
      <h1 className="text-3xl font-black text-zinc-900 mb-8">Subjects</h1>

      <div className="bg-zinc-50 border-2 border-black rounded-xl p-6 mb-8 shadow-[4px_4px_0_0_#000]">
        <h3 className="font-black text-zinc-800 text-lg mb-4">Add Subject</h3>
        <div className="flex gap-4 flex-wrap">
          <input placeholder="Code (e.g. CEUC102)" value={form.code} onChange={e => setForm(f => ({ ...f, code: e.target.value }))} className={`${inp} w-44`} />
          <input placeholder="Subject Name" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} className={`${inp} flex-1 min-w-48`} />
          <select value={form.subject_type} onChange={e => setForm(f => ({ ...f, subject_type: e.target.value }))} className={`${inp} w-36`}>
            <option value="lecture">Lecture</option>
            <option value="lab">Lab</option>
          </select>
          <button onClick={() => mut.mutate()} disabled={!form.code || !form.name}
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
              {['Code', 'Name', 'Type'].map(h => (
                <th key={h} className="px-5 py-4 text-left text-sm font-bold uppercase tracking-wider">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-200">
            {subjects.map((s: any) => (
              <tr key={s.id} className="hover:bg-zinc-100">
                <td className="px-5 py-3.5 font-mono text-sm text-zinc-500">{s.code}</td>
                <td className="px-5 py-3.5 font-semibold text-zinc-900">{s.name}</td>
                <td className="px-5 py-3.5">
                  <span className={`text-sm font-bold px-3 py-1 rounded-lg border-2 border-black ${s.subject_type === 'lab' ? 'bg-indigo-100 text-indigo-900' : 'bg-zinc-100 text-zinc-700'}`}>
                    {s.subject_type === 'lab' ? 'Lab' : 'Lecture'}
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
