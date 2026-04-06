import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { adminListAdmins, adminCreateAdmin } from '../../api/endpoints'
import { useAuth } from '../../components/AuthContext'

const inp = "border-2 border-black rounded-lg px-4 py-3 text-base focus:outline-none focus:ring-2 focus:ring-indigo-400 shadow-[2px_2px_0_0_#000] bg-white"

export default function Admins() {
  const { user } = useAuth()
  const qc = useQueryClient()
  const { data: admins = [] } = useQuery({ queryKey: ['admins'], queryFn: adminListAdmins })
  const [form, setForm] = useState({ full_name: '', admin_id: '', password: 'Pass@123', is_super_admin: false })
  const [err, setErr] = useState('')

  const mut = useMutation({
    mutationFn: () => adminCreateAdmin(form),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['admins'] }); setForm({ full_name: '', admin_id: '', password: 'Pass@123', is_super_admin: false }); setErr('') },
    onError: (e: any) => setErr(e.response?.data?.detail || 'Error'),
  })

  return (
    <div className="p-8 max-w-4xl mx-auto">
      <h1 className="text-3xl font-black text-zinc-900 mb-8">Admin Accounts</h1>

      <div className="bg-zinc-50 border-2 border-black rounded-xl p-6 mb-8 shadow-[4px_4px_0_0_#000]">
        <h3 className="font-black text-zinc-800 text-lg mb-4">Add Admin</h3>
        <div className="flex gap-4 flex-wrap items-end">
          <input placeholder="Full Name" value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))} className={`${inp} flex-1 min-w-48`} />
          <input placeholder="Admin ID (e.g. ADMIN002)" value={form.admin_id} onChange={e => setForm(f => ({ ...f, admin_id: e.target.value }))} className={`${inp} w-44`} />
          <input placeholder="Password" value={form.password} onChange={e => setForm(f => ({ ...f, password: e.target.value }))} className={`${inp} w-40`} />
          {user?.is_super_admin && (
            <label className="flex items-center gap-2 text-base text-zinc-700 cursor-pointer font-medium">
              <input type="checkbox" checked={form.is_super_admin} onChange={e => setForm(f => ({ ...f, is_super_admin: e.target.checked }))} className="w-4 h-4" />
              Super Admin
            </label>
          )}
          <button onClick={() => mut.mutate()} disabled={!form.full_name || !form.admin_id}
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
              {['Admin ID', 'Name', 'Role'].map(h => (
                <th key={h} className="px-5 py-4 text-left text-sm font-bold uppercase tracking-wider">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-200">
            {admins.map((a: any) => (
              <tr key={a.id} className="hover:bg-zinc-100">
                <td className="px-5 py-3.5 font-mono text-sm text-zinc-500">{a.admin_id}</td>
                <td className="px-5 py-3.5 font-semibold text-zinc-900">{a.full_name}</td>
                <td className="px-5 py-3.5">
                  {a.is_super_admin
                    ? <span className="bg-indigo-100 border-2 border-black text-indigo-900 text-sm font-bold px-3 py-1 rounded-lg">Super Admin</span>
                    : <span className="bg-zinc-100 border border-zinc-300 text-zinc-600 text-sm font-medium px-3 py-1 rounded-lg">Admin</span>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
