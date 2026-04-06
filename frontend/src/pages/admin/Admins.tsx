import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { adminListAdmins, adminCreateAdmin } from '../../api/endpoints'
import { useAuth } from '../../components/AuthContext'

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
    <div style={{ padding: 24 }}>
      <h2>Admin Accounts</h2>
      <div style={{ border: '1px solid #ddd', borderRadius: 8, padding: 16, maxWidth: 420, marginBottom: 24 }}>
        <h4 style={{ margin: '0 0 12px' }}>Add Admin</h4>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <input placeholder="Full Name" value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))} />
          <input placeholder="Admin ID (e.g. ADMIN002)" value={form.admin_id} onChange={e => setForm(f => ({ ...f, admin_id: e.target.value }))} />
          <input placeholder="Password" value={form.password} onChange={e => setForm(f => ({ ...f, password: e.target.value }))} />
          {user?.is_super_admin && (
            <label style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <input type="checkbox" checked={form.is_super_admin} onChange={e => setForm(f => ({ ...f, is_super_admin: e.target.checked }))} />
              Super Admin
            </label>
          )}
          {err && <span style={{ color: 'red', fontSize: 13 }}>{err}</span>}
          <button onClick={() => mut.mutate()} disabled={!form.full_name || !form.admin_id}>Add Admin</button>
        </div>
      </div>

      <table style={{ borderCollapse: 'collapse', fontSize: 14 }}>
        <thead>
          <tr style={{ background: '#f5f5f5' }}>
            {['Admin ID', 'Name', 'Super Admin'].map(h => (
              <th key={h} style={{ padding: '8px 16px', textAlign: 'left', borderBottom: '1px solid #ddd' }}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {admins.map((a: any) => (
            <tr key={a.id}>
              <td style={{ padding: '6px 16px' }}>{a.admin_id}</td>
              <td style={{ padding: '6px 16px' }}>{a.full_name}</td>
              <td style={{ padding: '6px 16px' }}>{a.is_super_admin ? '✓' : '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
