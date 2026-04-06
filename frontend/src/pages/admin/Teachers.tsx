import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { adminListTeachers, adminCreateTeacher } from '../../api/endpoints'

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
    <div style={{ padding: 24 }}>
      <h2>Teachers</h2>
      <div style={{ border: '1px solid #ddd', borderRadius: 8, padding: 16, maxWidth: 420, marginBottom: 24 }}>
        <h4 style={{ margin: '0 0 12px' }}>Add Teacher</h4>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <input placeholder="Full Name" value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))} />
          <input placeholder="Teacher ID (e.g. T002)" value={form.teacher_id} onChange={e => setForm(f => ({ ...f, teacher_id: e.target.value }))} />
          <input placeholder="Password" value={form.password} onChange={e => setForm(f => ({ ...f, password: e.target.value }))} />
          {err && <span style={{ color: 'red', fontSize: 13 }}>{err}</span>}
          <button onClick={() => mut.mutate()} disabled={!form.full_name || !form.teacher_id}>Add Teacher</button>
        </div>
      </div>

      <table style={{ borderCollapse: 'collapse', fontSize: 14 }}>
        <thead>
          <tr style={{ background: '#f5f5f5' }}>
            {['Teacher ID', 'Name'].map(h => (
              <th key={h} style={{ padding: '8px 16px', textAlign: 'left', borderBottom: '1px solid #ddd' }}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {teachers.map((t: any) => (
            <tr key={t.id}>
              <td style={{ padding: '6px 16px' }}>{t.teacher_id}</td>
              <td style={{ padding: '6px 16px' }}>{t.full_name}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
