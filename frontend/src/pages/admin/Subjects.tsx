import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { listSubjects, createSubject } from '../../api/endpoints'

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
    <div style={{ padding: 24 }}>
      <h2>Subjects</h2>
      <div style={{ border: '1px solid #ddd', borderRadius: 8, padding: 16, maxWidth: 460, marginBottom: 24 }}>
        <h4 style={{ margin: '0 0 12px' }}>Add Subject</h4>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <input placeholder="Code (e.g. CEUC102)" value={form.code} onChange={e => setForm(f => ({ ...f, code: e.target.value }))} />
          <input placeholder="Name" value={form.name} onChange={e => setForm(f => ({ ...f, name: e.target.value }))} />
          <select value={form.subject_type} onChange={e => setForm(f => ({ ...f, subject_type: e.target.value }))}>
            <option value="lecture">Lecture</option>
            <option value="lab">Lab</option>
          </select>
          {err && <span style={{ color: 'red', fontSize: 13 }}>{err}</span>}
          <button onClick={() => mut.mutate()} disabled={!form.code || !form.name}>Add Subject</button>
        </div>
      </div>

      <table style={{ borderCollapse: 'collapse', fontSize: 14 }}>
        <thead>
          <tr style={{ background: '#f5f5f5' }}>
            {['Code', 'Name', 'Type'].map(h => (
              <th key={h} style={{ padding: '8px 16px', textAlign: 'left', borderBottom: '1px solid #ddd' }}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {subjects.map((s: any) => (
            <tr key={s.id}>
              <td style={{ padding: '6px 16px' }}>{s.code}</td>
              <td style={{ padding: '6px 16px' }}>{s.name}</td>
              <td style={{ padding: '6px 16px', textTransform: 'capitalize' }}>{s.subject_type}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
