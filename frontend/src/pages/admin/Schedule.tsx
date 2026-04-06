import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  listSemesters, createSemester, activateSemester,
  listBranches, createBranch,
  listDivisions, createDivision,
  listBatches, createBatch,
  listSubjects, adminListTeachers,
  listAssignments, createAssignment, deleteAssignment,
  listSlots, createSlot, deleteSlot,
} from '../../api/endpoints'

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const TIME_SLOTS = ['09:10', '10:10', '11:10', '12:10', '13:10', '14:20', '15:20']
const TIME_ENDS:  Record<string, string> = {
  '09:10': '10:10', '10:10': '11:10', '11:10': '12:10',
  '12:10': '13:10', '13:10': '14:10', '14:20': '15:20', '15:20': '16:20',
}

type Tab = 'semesters' | 'branches' | 'assignments' | 'slots'

export default function Schedule() {
  const qc = useQueryClient()
  const [tab, setTab] = useState<Tab>('semesters')

  // Data
  const { data: semesters = [] } = useQuery({ queryKey: ['semesters'], queryFn: listSemesters })
  const { data: branches = [] } = useQuery({ queryKey: ['branches'], queryFn: listBranches })
  const { data: divisions = [] } = useQuery({ queryKey: ['divisions'], queryFn: () => listDivisions() })
  const { data: subjects = [] } = useQuery({ queryKey: ['subjects'], queryFn: listSubjects })
  const { data: teachers = [] } = useQuery({ queryKey: ['teachers'], queryFn: adminListTeachers })
  const { data: assignments = [] } = useQuery({ queryKey: ['assignments'], queryFn: () => listAssignments() })

  const activeSem = semesters.find((s: any) => s.is_active)
  const { data: slots = [] } = useQuery({
    queryKey: ['slots', activeSem?.id],
    queryFn: () => listSlots({ semester_id: activeSem?.id }),
    enabled: !!activeSem,
  })

  // Semester form
  const [semForm, setSemForm] = useState({ name: '', start_date: '', end_date: '', is_active: false })
  const semMut = useMutation({ mutationFn: () => createSemester(semForm), onSuccess: () => { qc.invalidateQueries({ queryKey: ['semesters'] }); setSemForm({ name: '', start_date: '', end_date: '', is_active: false }) } })
  const activateMut = useMutation({ mutationFn: (id: number) => activateSemester(id), onSuccess: () => qc.invalidateQueries({ queryKey: ['semesters'] }) })

  // Branch form
  const [branchForm, setBranchForm] = useState({ code: '', name: '' })
  const branchMut = useMutation({ mutationFn: () => createBranch(branchForm), onSuccess: () => { qc.invalidateQueries({ queryKey: ['branches'] }); setBranchForm({ code: '', name: '' }) } })

  // Division form
  const [divForm, setDivForm] = useState({ branch_id: '', year: '1', div_number: '1', label: '' })
  const divMut = useMutation({
    mutationFn: () => createDivision({ branch_id: Number(divForm.branch_id), year: Number(divForm.year), div_number: Number(divForm.div_number), label: divForm.label }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['divisions'] }); setDivForm({ branch_id: '', year: '1', div_number: '1', label: '' }) },
  })

  // Batch form
  const [batchDivId, setBatchDivId] = useState('')
  const { data: batchesForDiv = [] } = useQuery({ queryKey: ['batches', batchDivId], queryFn: () => listBatches(Number(batchDivId)), enabled: !!batchDivId })
  const [batchLabel, setBatchLabel] = useState('')
  const batchMut = useMutation({ mutationFn: () => createBatch({ division_id: Number(batchDivId), label: batchLabel }), onSuccess: () => { qc.invalidateQueries({ queryKey: ['batches', batchDivId] }); setBatchLabel('') } })

  // Assignment form
  const [aForm, setAForm] = useState({ teacher_user_id: '', subject_id: '', division_id: '', batch_id: '' })
  const { data: batchesForAssign = [] } = useQuery({ queryKey: ['batches', aForm.division_id], queryFn: () => listBatches(Number(aForm.division_id)), enabled: !!aForm.division_id })
  const assignMut = useMutation({
    mutationFn: () => createAssignment({ teacher_user_id: aForm.teacher_user_id, subject_id: Number(aForm.subject_id), division_id: Number(aForm.division_id), batch_id: aForm.batch_id ? Number(aForm.batch_id) : undefined }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['assignments'] }); setAForm({ teacher_user_id: '', subject_id: '', division_id: '', batch_id: '' }) },
  })
  const delAssignMut = useMutation({ mutationFn: (id: number) => deleteAssignment(id), onSuccess: () => qc.invalidateQueries({ queryKey: ['assignments'] }) })

  // Slot form
  const [slotForm, setSlotForm] = useState({ assignment_id: '', day_of_week: '0', time_start: '09:10', room: '' })
  const slotMut = useMutation({
    mutationFn: () => createSlot({ assignment_id: Number(slotForm.assignment_id), semester_id: activeSem?.id, day_of_week: Number(slotForm.day_of_week), time_start: slotForm.time_start, time_end: TIME_ENDS[slotForm.time_start] || '10:10', room: slotForm.room }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['slots', activeSem?.id] }); setSlotForm({ assignment_id: '', day_of_week: '0', time_start: '09:10', room: '' }) },
  })
  const delSlotMut = useMutation({ mutationFn: (id: number) => deleteSlot(id), onSuccess: () => qc.invalidateQueries({ queryKey: ['slots', activeSem?.id] }) })

  const tabStyle = (t: Tab) => ({ padding: '8px 16px', cursor: 'pointer', borderBottom: tab === t ? '2px solid #0070f3' : '2px solid transparent', background: 'none', border: 'none', borderBottom: tab === t ? '2px solid #0070f3' : '2px solid transparent', fontWeight: tab === t ? 700 : 400 } as React.CSSProperties)

  return (
    <div style={{ padding: 24 }}>
      <h2>Schedule Management</h2>
      <div style={{ display: 'flex', gap: 4, marginBottom: 20, borderBottom: '1px solid #ddd' }}>
        {(['semesters', 'branches', 'assignments', 'slots'] as Tab[]).map(t => (
          <button key={t} style={tabStyle(t)} onClick={() => setTab(t)}>{t.charAt(0).toUpperCase() + t.slice(1)}</button>
        ))}
      </div>

      {tab === 'semesters' && (
        <div>
          <div style={{ border: '1px solid #ddd', borderRadius: 8, padding: 16, maxWidth: 460, marginBottom: 20 }}>
            <h4 style={{ margin: '0 0 10px' }}>Add Semester</h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <input placeholder="Name (e.g. Sem II 2025-26)" value={semForm.name} onChange={e => setSemForm(f => ({ ...f, name: e.target.value }))} />
              <div style={{ display: 'flex', gap: 8 }}>
                <input type="date" value={semForm.start_date} onChange={e => setSemForm(f => ({ ...f, start_date: e.target.value }))} style={{ flex: 1 }} />
                <input type="date" value={semForm.end_date} onChange={e => setSemForm(f => ({ ...f, end_date: e.target.value }))} style={{ flex: 1 }} />
              </div>
              <label style={{ display: 'flex', gap: 8 }}><input type="checkbox" checked={semForm.is_active} onChange={e => setSemForm(f => ({ ...f, is_active: e.target.checked }))} /> Set as active</label>
              <button onClick={() => semMut.mutate()} disabled={!semForm.name}>Add</button>
            </div>
          </div>
          <table style={{ borderCollapse: 'collapse', fontSize: 14 }}>
            <thead><tr style={{ background: '#f5f5f5' }}>{['Name', 'Start', 'End', 'Active', ''].map(h => <th key={h} style={{ padding: '8px 12px', textAlign: 'left', borderBottom: '1px solid #ddd' }}>{h}</th>)}</tr></thead>
            <tbody>
              {semesters.map((s: any) => (
                <tr key={s.id}>
                  <td style={{ padding: '6px 12px' }}>{s.name}</td>
                  <td style={{ padding: '6px 12px' }}>{s.start_date}</td>
                  <td style={{ padding: '6px 12px' }}>{s.end_date}</td>
                  <td style={{ padding: '6px 12px' }}>{s.is_active ? '✓' : ''}</td>
                  <td style={{ padding: '6px 12px' }}>{!s.is_active && <button onClick={() => activateMut.mutate(s.id)} style={{ fontSize: 12 }}>Activate</button>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {tab === 'branches' && (
        <div style={{ display: 'flex', gap: 32, flexWrap: 'wrap' }}>
          <div>
            <h4>Branches</h4>
            <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
              <input placeholder="Code (CE)" value={branchForm.code} onChange={e => setBranchForm(f => ({ ...f, code: e.target.value }))} style={{ width: 80 }} />
              <input placeholder="Name" value={branchForm.name} onChange={e => setBranchForm(f => ({ ...f, name: e.target.value }))} />
              <button onClick={() => branchMut.mutate()}>Add</button>
            </div>
            <table style={{ borderCollapse: 'collapse', fontSize: 14 }}>
              <thead><tr style={{ background: '#f5f5f5' }}>{['Code', 'Name'].map(h => <th key={h} style={{ padding: '6px 12px', borderBottom: '1px solid #ddd' }}>{h}</th>)}</tr></thead>
              <tbody>{branches.map((b: any) => <tr key={b.id}><td style={{ padding: '5px 12px' }}>{b.code}</td><td style={{ padding: '5px 12px' }}>{b.name}</td></tr>)}</tbody>
            </table>
          </div>

          <div>
            <h4>Divisions</h4>
            <div style={{ display: 'flex', gap: 8, marginBottom: 12, flexWrap: 'wrap' }}>
              <select value={divForm.branch_id} onChange={e => setDivForm(f => ({ ...f, branch_id: e.target.value }))} style={{ padding: 6 }}>
                <option value="">Branch</option>
                {branches.map((b: any) => <option key={b.id} value={b.id}>{b.code}</option>)}
              </select>
              <select value={divForm.year} onChange={e => setDivForm(f => ({ ...f, year: e.target.value }))} style={{ padding: 6 }}>
                {[1,2,3,4].map(y => <option key={y} value={y}>Year {y}</option>)}
              </select>
              <input placeholder="Div #" value={divForm.div_number} onChange={e => setDivForm(f => ({ ...f, div_number: e.target.value }))} style={{ width: 60 }} />
              <input placeholder="Label (CE-FY-Div1)" value={divForm.label} onChange={e => setDivForm(f => ({ ...f, label: e.target.value }))} style={{ width: 140 }} />
              <button onClick={() => divMut.mutate()}>Add</button>
            </div>
            <table style={{ borderCollapse: 'collapse', fontSize: 14 }}>
              <thead><tr style={{ background: '#f5f5f5' }}>{['Label', 'Year', 'Div'].map(h => <th key={h} style={{ padding: '6px 12px', borderBottom: '1px solid #ddd' }}>{h}</th>)}</tr></thead>
              <tbody>{divisions.map((d: any) => <tr key={d.id}><td style={{ padding: '5px 12px' }}>{d.label}</td><td style={{ padding: '5px 12px' }}>{d.year}</td><td style={{ padding: '5px 12px' }}>{d.div_number}</td></tr>)}</tbody>
            </table>
          </div>

          <div>
            <h4>Batches</h4>
            <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
              <select value={batchDivId} onChange={e => setBatchDivId(e.target.value)} style={{ padding: 6 }}>
                <option value="">Division</option>
                {divisions.map((d: any) => <option key={d.id} value={d.id}>{d.label}</option>)}
              </select>
              <input placeholder="Label (A1)" value={batchLabel} onChange={e => setBatchLabel(e.target.value)} style={{ width: 80 }} />
              <button onClick={() => batchMut.mutate()} disabled={!batchDivId || !batchLabel}>Add</button>
            </div>
            {batchDivId && <div style={{ fontSize: 13 }}>{batchesForDiv.map((b: any) => <span key={b.id} style={{ marginRight: 8, padding: '2px 8px', background: '#eee', borderRadius: 4 }}>{b.label}</span>)}</div>}
          </div>
        </div>
      )}

      {tab === 'assignments' && (
        <div>
          <div style={{ border: '1px solid #ddd', borderRadius: 8, padding: 16, maxWidth: 560, marginBottom: 20 }}>
            <h4 style={{ margin: '0 0 10px' }}>Assign Teacher to Subject+Division</h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <select value={aForm.teacher_user_id} onChange={e => setAForm(f => ({ ...f, teacher_user_id: e.target.value }))} style={{ padding: 6 }}>
                <option value="">Teacher</option>
                {teachers.map((t: any) => <option key={t.id} value={t.id}>{t.full_name} ({t.teacher_id})</option>)}
              </select>
              <select value={aForm.subject_id} onChange={e => setAForm(f => ({ ...f, subject_id: e.target.value }))} style={{ padding: 6 }}>
                <option value="">Subject</option>
                {subjects.map((s: any) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}
              </select>
              <select value={aForm.division_id} onChange={e => setAForm(f => ({ ...f, division_id: e.target.value, batch_id: '' }))} style={{ padding: 6 }}>
                <option value="">Division</option>
                {divisions.map((d: any) => <option key={d.id} value={d.id}>{d.label}</option>)}
              </select>
              {aForm.division_id && (
                <select value={aForm.batch_id} onChange={e => setAForm(f => ({ ...f, batch_id: e.target.value }))} style={{ padding: 6 }}>
                  <option value="">No batch (lecture)</option>
                  {batchesForAssign.map((b: any) => <option key={b.id} value={b.id}>{b.label}</option>)}
                </select>
              )}
              <button onClick={() => assignMut.mutate()} disabled={!aForm.teacher_user_id || !aForm.subject_id || !aForm.division_id}>Assign</button>
            </div>
          </div>
          <table style={{ borderCollapse: 'collapse', fontSize: 14 }}>
            <thead><tr style={{ background: '#f5f5f5' }}>{['Teacher', 'Subject', 'Division', 'Batch', ''].map(h => <th key={h} style={{ padding: '8px 12px', textAlign: 'left', borderBottom: '1px solid #ddd' }}>{h}</th>)}</tr></thead>
            <tbody>
              {assignments.map((a: any) => (
                <tr key={a.id}>
                  <td style={{ padding: '6px 12px' }}>{a.teacher_name}</td>
                  <td style={{ padding: '6px 12px' }}>{a.subject_code}</td>
                  <td style={{ padding: '6px 12px' }}>{a.division_label}</td>
                  <td style={{ padding: '6px 12px' }}>{a.batch_label || '—'}</td>
                  <td style={{ padding: '6px 12px' }}><button onClick={() => delAssignMut.mutate(a.id)} style={{ color: 'red', fontSize: 12 }}>Delete</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {tab === 'slots' && (
        <div>
          {!activeSem && <p style={{ color: 'orange' }}>No active semester. Activate one first.</p>}
          {activeSem && (
            <>
              <p style={{ color: '#555', marginBottom: 12 }}>Active semester: <strong>{activeSem.name}</strong></p>
              <div style={{ border: '1px solid #ddd', borderRadius: 8, padding: 16, maxWidth: 560, marginBottom: 20 }}>
                <h4 style={{ margin: '0 0 10px' }}>Add Schedule Slot</h4>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  <select value={slotForm.assignment_id} onChange={e => setSlotForm(f => ({ ...f, assignment_id: e.target.value }))} style={{ padding: 6 }}>
                    <option value="">Assignment</option>
                    {assignments.map((a: any) => <option key={a.id} value={a.id}>{a.teacher_name} · {a.subject_code} · {a.division_label}{a.batch_label ? ` · ${a.batch_label}` : ''}</option>)}
                  </select>
                  <div style={{ display: 'flex', gap: 8 }}>
                    <select value={slotForm.day_of_week} onChange={e => setSlotForm(f => ({ ...f, day_of_week: e.target.value }))} style={{ padding: 6, flex: 1 }}>
                      {DAYS.map((d, i) => <option key={i} value={i}>{d}</option>)}
                    </select>
                    <select value={slotForm.time_start} onChange={e => setSlotForm(f => ({ ...f, time_start: e.target.value }))} style={{ padding: 6, flex: 1 }}>
                      {TIME_SLOTS.map(t => <option key={t} value={t}>{t}</option>)}
                    </select>
                    <input placeholder="Room" value={slotForm.room} onChange={e => setSlotForm(f => ({ ...f, room: e.target.value }))} style={{ width: 80 }} />
                  </div>
                  <button onClick={() => slotMut.mutate()} disabled={!slotForm.assignment_id}>Add Slot</button>
                </div>
              </div>

              {/* Timetable grid */}
              <div style={{ overflowX: 'auto' }}>
                <table style={{ borderCollapse: 'collapse', fontSize: 12, minWidth: 700 }}>
                  <thead>
                    <tr>
                      <th style={{ padding: '6px 10px', border: '1px solid #ddd', background: '#f5f5f5' }}>Time</th>
                      {DAYS.map(d => <th key={d} style={{ padding: '6px 10px', border: '1px solid #ddd', background: '#f5f5f5', minWidth: 100 }}>{d}</th>)}
                    </tr>
                  </thead>
                  <tbody>
                    {TIME_SLOTS.map(ts => (
                      <tr key={ts}>
                        <td style={{ padding: '6px 10px', border: '1px solid #ddd', fontWeight: 600, whiteSpace: 'nowrap' }}>{ts}</td>
                        {DAYS.map((_, di) => {
                          const daySlots = slots.filter((s: any) => s.day_of_week === di && s.time_start === ts)
                          return (
                            <td key={di} style={{ padding: '4px 6px', border: '1px solid #ddd', verticalAlign: 'top' }}>
                              {daySlots.map((s: any) => (
                                <div key={s.id} style={{ background: '#e8f4fd', borderRadius: 4, padding: '2px 6px', marginBottom: 2, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                  <span>{s.subject_code}{s.batch_label ? ` (${s.batch_label})` : ''}</span>
                                  <button onClick={() => delSlotMut.mutate(s.id)} style={{ background: 'none', border: 'none', color: 'red', cursor: 'pointer', fontSize: 11, padding: 0, marginLeft: 4 }}>✕</button>
                                </div>
                              ))}
                            </td>
                          )
                        })}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  )
}
