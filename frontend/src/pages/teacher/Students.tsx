import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { listDivisions, listBatches, getDivisionStudents, addStudent } from '../../api/endpoints'

export default function Students() {
  const qc = useQueryClient()
  const { data: divisions = [] } = useQuery({ queryKey: ['divisions'], queryFn: () => listDivisions() })
  const [divId, setDivId] = useState<number | ''>('')
  const { data: batches = [] } = useQuery({ queryKey: ['batches', divId], queryFn: () => listBatches(divId as number), enabled: !!divId })
  const { data: students = [] } = useQuery({ queryKey: ['students', divId], queryFn: () => getDivisionStudents(divId as number), enabled: !!divId })

  const [form, setForm] = useState({ full_name: '', student_id: '', batch_id: '' })
  const [err, setErr] = useState('')

  const addMut = useMutation({
    mutationFn: () => addStudent({
      full_name: form.full_name, student_id: form.student_id,
      division_id: divId as number,
      batch_id: form.batch_id ? Number(form.batch_id) : undefined,
    }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['students', divId] }); setForm({ full_name: '', student_id: '', batch_id: '' }); setErr('') },
    onError: (e: any) => setErr(e.response?.data?.detail || 'Error'),
  })

  return (
    <div style={{ padding: 24 }}>
      <h2>Student Management</h2>
      <div style={{ marginBottom: 16 }}>
        <label>Division: </label>
        <select value={divId} onChange={e => setDivId(Number(e.target.value))} style={{ padding: 6, marginLeft: 8 }}>
          <option value="">— Select —</option>
          {divisions.map((d: any) => <option key={d.id} value={d.id}>{d.label}</option>)}
        </select>
      </div>

      {divId && (
        <>
          <div style={{ border: '1px solid #ddd', borderRadius: 8, padding: 16, marginBottom: 20, maxWidth: 500 }}>
            <h4 style={{ margin: '0 0 12px' }}>Add Student</h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <input placeholder="Full Name" value={form.full_name} onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))} />
              <input placeholder="Student ID (e.g. 25CE099)" value={form.student_id} onChange={e => setForm(f => ({ ...f, student_id: e.target.value }))} />
              <select value={form.batch_id} onChange={e => setForm(f => ({ ...f, batch_id: e.target.value }))}>
                <option value="">No batch (lecture)</option>
                {batches.map((b: any) => <option key={b.id} value={b.id}>{b.label}</option>)}
              </select>
              {err && <span style={{ color: 'red', fontSize: 13 }}>{err}</span>}
              <button onClick={() => addMut.mutate()} disabled={!form.full_name || !form.student_id}>Add Student</button>
            </div>
          </div>

          <table style={{ width: '100%', maxWidth: 600, borderCollapse: 'collapse', fontSize: 14 }}>
            <thead>
              <tr style={{ background: '#f5f5f5' }}>
                {['Student ID', 'Name', 'Batch'].map(h => (
                  <th key={h} style={{ padding: '8px 10px', textAlign: 'left', borderBottom: '1px solid #ddd' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {students.map((s: any) => (
                <tr key={s.id}>
                  <td style={{ padding: '6px 10px' }}>{s.student_id}</td>
                  <td style={{ padding: '6px 10px' }}>{s.full_name}</td>
                  <td style={{ padding: '6px 10px' }}>{batches.find((b: any) => b.id === s.batch_id)?.label || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </div>
  )
}
