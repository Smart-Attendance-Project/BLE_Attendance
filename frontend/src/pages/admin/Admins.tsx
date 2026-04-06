import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { adminListAdmins, adminCreateAdmin } from '../../api/endpoints'
import { useAuth } from '../../components/AuthContext'
import { ShieldCheck } from 'lucide-react'

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
    <div className="p-6 max-w-3xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Admin Accounts</h1>

      <div className="bg-white border border-gray-200 rounded-xl p-5 mb-6">
        <h3 className="font-semibold text-gray-800 mb-4 flex items-center gap-2"><ShieldCheck size={16} />Add Admin</h3>
        <div className="flex gap-3 flex-wrap items-end">
          <input placeholder="Full Name" value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))}
            className="flex-1 min-w-40 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          <input placeholder="Admin ID (e.g. ADMIN002)" value={form.admin_id} onChange={e => setForm(f => ({ ...f, admin_id: e.target.value }))}
            className="w-40 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          <input placeholder="Password" value={form.password} onChange={e => setForm(f => ({ ...f, password: e.target.value }))}
            className="w-36 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          {user?.is_super_admin && (
            <label className="flex items-center gap-2 text-sm text-gray-700 cursor-pointer">
              <input type="checkbox" checked={form.is_super_admin} onChange={e => setForm(f => ({ ...f, is_super_admin: e.target.checked }))} className="rounded" />
              Super Admin
            </label>
          )}
          <button onClick={() => mut.mutate()} disabled={!form.full_name || !form.admin_id}
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
              {['Admin ID', 'Name', 'Role'].map(h => (
                <th key={h} className="px-4 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {admins.map((a: any) => (
              <tr key={a.id} className="hover:bg-gray-50">
                <td className="px-4 py-2.5 font-mono text-xs text-gray-600">{a.admin_id}</td>
                <td className="px-4 py-2.5 font-medium text-gray-900">{a.full_name}</td>
                <td className="px-4 py-2.5">
                  {a.is_super_admin
                    ? <span className="bg-purple-100 text-purple-700 text-xs font-medium px-2 py-0.5 rounded-full">Super Admin</span>
                    : <span className="bg-gray-100 text-gray-600 text-xs font-medium px-2 py-0.5 rounded-full">Admin</span>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
