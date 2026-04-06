import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Trash2, Plus } from 'lucide-react'
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
const TIME_ENDS: Record<string, string> = {
  '09:10': '10:10', '10:10': '11:10', '11:10': '12:10',
  '12:10': '13:10', '13:10': '14:10', '14:20': '15:20', '15:20': '16:20',
}
type Tab = 'semesters' | 'branches' | 'assignments' | 'timetable'

const inp = "border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
const btn = "bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white text-sm font-medium px-4 py-2 rounded-lg transition-colors"

export default function Schedule() {
  const qc = useQueryClient()
  const [tab, setTab] = useState<Tab>('semesters')

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

  // Semester
  const [semForm, setSemForm] = useState({ name: '', start_date: '', end_date: '', is_active: false })
  const semMut = useMutation({ mutationFn: () => createSemester(semForm), onSuccess: () => { qc.invalidateQueries({ queryKey: ['semesters'] }); setSemForm({ name: '', start_date: '', end_date: '', is_active: false }) } })
  const activateMut = useMutation({ mutationFn: (id: number) => activateSemester(id), onSuccess: () => qc.invalidateQueries({ queryKey: ['semesters'] }) })

  // Branch
  const [branchForm, setBranchForm] = useState({ code: '', name: '' })
  const branchMut = useMutation({ mutationFn: () => createBranch(branchForm), onSuccess: () => { qc.invalidateQueries({ queryKey: ['branches'] }); setBranchForm({ code: '', name: '' }) } })

  // Division
  const [divForm, setDivForm] = useState({ branch_id: '', year: '1', div_number: '1', label: '' })
  const divMut = useMutation({
    mutationFn: () => createDivision({ branch_id: Number(divForm.branch_id), year: Number(divForm.year), div_number: Number(divForm.div_number), label: divForm.label }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['divisions'] }); setDivForm({ branch_id: '', year: '1', div_number: '1', label: '' }) },
  })

  // Batch
  const [batchDivId, setBatchDivId] = useState('')
  const { data: batchesForDiv = [] } = useQuery({ queryKey: ['batches', batchDivId], queryFn: () => listBatches(Number(batchDivId)), enabled: !!batchDivId })
  const [batchLabel, setBatchLabel] = useState('')
  const batchMut = useMutation({ mutationFn: () => createBatch({ division_id: Number(batchDivId), label: batchLabel }), onSuccess: () => { qc.invalidateQueries({ queryKey: ['batches', batchDivId] }); setBatchLabel('') } })

  // Assignment
  const [aForm, setAForm] = useState({ teacher_user_id: '', subject_id: '', division_id: '', batch_id: '' })
  const { data: batchesForAssign = [] } = useQuery({ queryKey: ['batches', aForm.division_id], queryFn: () => listBatches(Number(aForm.division_id)), enabled: !!aForm.division_id })
  const assignMut = useMutation({
    mutationFn: () => createAssignment({ teacher_user_id: aForm.teacher_user_id, subject_id: Number(aForm.subject_id), division_id: Number(aForm.division_id), batch_id: aForm.batch_id ? Number(aForm.batch_id) : undefined }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['assignments'] }); setAForm({ teacher_user_id: '', subject_id: '', division_id: '', batch_id: '' }) },
  })
  const delAssignMut = useMutation({ mutationFn: (id: number) => deleteAssignment(id), onSuccess: () => qc.invalidateQueries({ queryKey: ['assignments'] }) })

  // Slot
  const [slotForm, setSlotForm] = useState({ assignment_id: '', day_of_week: '0', time_start: '09:10', room: '' })
  const slotMut = useMutation({
    mutationFn: () => createSlot({ assignment_id: Number(slotForm.assignment_id), semester_id: activeSem?.id, day_of_week: Number(slotForm.day_of_week), time_start: slotForm.time_start, time_end: TIME_ENDS[slotForm.time_start] || '10:10', room: slotForm.room }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['slots', activeSem?.id] }); setSlotForm({ assignment_id: '', day_of_week: '0', time_start: '09:10', room: '' }) },
  })
  const delSlotMut = useMutation({ mutationFn: (id: number) => deleteSlot(id), onSuccess: () => qc.invalidateQueries({ queryKey: ['slots', activeSem?.id] }) })

  const tabs: { key: Tab; label: string }[] = [
    { key: 'semesters', label: 'Semesters' },
    { key: 'branches', label: 'Branches & Divisions' },
    { key: 'assignments', label: 'Assignments' },
    { key: 'timetable', label: 'Timetable' },
  ]

  return (
    <div className="p-6 max-w-6xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Schedule Management</h1>

      <div className="flex gap-1 mb-6 border-b border-gray-200">
        {tabs.map(t => (
          <button key={t.key} onClick={() => setTab(t.key)}
            className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors -mb-px ${tab === t.key ? 'border-indigo-600 text-indigo-600' : 'border-transparent text-gray-500 hover:text-gray-700'}`}>
            {t.label}
          </button>
        ))}
      </div>

      {/* ── Semesters ── */}
      {tab === 'semesters' && (
        <div className="max-w-2xl">
          <div className="bg-white border border-gray-200 rounded-xl p-5 mb-5">
            <h3 className="font-semibold text-gray-800 mb-4">Add Semester</h3>
            <div className="flex flex-col gap-3">
              <input className={inp} placeholder="Name (e.g. Sem II 2025-26)" value={semForm.name} onChange={e => setSemForm(f => ({ ...f, name: e.target.value }))} />
              <div className="flex gap-3">
                <input type="date" className={`${inp} flex-1`} value={semForm.start_date} onChange={e => setSemForm(f => ({ ...f, start_date: e.target.value }))} />
                <input type="date" className={`${inp} flex-1`} value={semForm.end_date} onChange={e => setSemForm(f => ({ ...f, end_date: e.target.value }))} />
              </div>
              <div className="flex items-center justify-between">
                <label className="flex items-center gap-2 text-sm text-gray-700 cursor-pointer">
                  <input type="checkbox" checked={semForm.is_active} onChange={e => setSemForm(f => ({ ...f, is_active: e.target.checked }))} />
                  Set as active semester
                </label>
                <button className={btn} onClick={() => semMut.mutate()} disabled={!semForm.name}>Add</button>
              </div>
            </div>
          </div>
          <div className="bg-white border border-gray-200 rounded-xl overflow-hidden">
            <table className="w-full text-sm">
              <thead><tr className="bg-gray-50 border-b border-gray-200">{['Name','Start','End','Status',''].map(h=><th key={h} className="px-4 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>)}</tr></thead>
              <tbody className="divide-y divide-gray-100">
                {semesters.map((s: any) => (
                  <tr key={s.id} className="hover:bg-gray-50">
                    <td className="px-4 py-2.5 font-medium text-gray-900">{s.name}</td>
                    <td className="px-4 py-2.5 text-gray-600">{s.start_date}</td>
                    <td className="px-4 py-2.5 text-gray-600">{s.end_date}</td>
                    <td className="px-4 py-2.5">{s.is_active ? <span className="bg-green-100 text-green-700 text-xs font-medium px-2 py-0.5 rounded-full">Active</span> : <span className="text-gray-400 text-xs">Inactive</span>}</td>
                    <td className="px-4 py-2.5">{!s.is_active && <button onClick={() => activateMut.mutate(s.id)} className="text-xs text-indigo-600 hover:underline">Activate</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ── Branches & Divisions ── */}
      {tab === 'branches' && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="bg-white border border-gray-200 rounded-xl p-5">
            <h3 className="font-semibold text-gray-800 mb-4">Branches</h3>
            <div className="flex gap-2 mb-4">
              <input className={`${inp} w-20`} placeholder="Code" value={branchForm.code} onChange={e => setBranchForm(f => ({ ...f, code: e.target.value }))} />
              <input className={`${inp} flex-1`} placeholder="Name" value={branchForm.name} onChange={e => setBranchForm(f => ({ ...f, name: e.target.value }))} />
              <button className={btn} onClick={() => branchMut.mutate()}>+</button>
            </div>
            <div className="flex flex-col gap-1">
              {branches.map((b: any) => <div key={b.id} className="flex items-center justify-between py-1.5 px-2 rounded-lg hover:bg-gray-50 text-sm"><span className="font-mono text-xs text-gray-500 w-12">{b.code}</span><span className="text-gray-700">{b.name}</span></div>)}
            </div>
          </div>

          <div className="bg-white border border-gray-200 rounded-xl p-5">
            <h3 className="font-semibold text-gray-800 mb-4">Divisions</h3>
            <div className="flex flex-col gap-2 mb-4">
              <select className={inp} value={divForm.branch_id} onChange={e => setDivForm(f => ({ ...f, branch_id: e.target.value }))}>
                <option value="">Branch</option>
                {branches.map((b: any) => <option key={b.id} value={b.id}>{b.code}</option>)}
              </select>
              <div className="flex gap-2">
                <select className={`${inp} flex-1`} value={divForm.year} onChange={e => setDivForm(f => ({ ...f, year: e.target.value }))}>
                  {[1,2,3,4].map(y => <option key={y} value={y}>Year {y}</option>)}
                </select>
                <input className={`${inp} w-16`} placeholder="Div#" value={divForm.div_number} onChange={e => setDivForm(f => ({ ...f, div_number: e.target.value }))} />
              </div>
              <div className="flex gap-2">
                <input className={`${inp} flex-1`} placeholder="Label (CE-FY-Div1)" value={divForm.label} onChange={e => setDivForm(f => ({ ...f, label: e.target.value }))} />
                <button className={btn} onClick={() => divMut.mutate()}>+</button>
              </div>
            </div>
            <div className="flex flex-col gap-1">
              {divisions.map((d: any) => <div key={d.id} className="py-1.5 px-2 rounded-lg hover:bg-gray-50 text-sm text-gray-700">{d.label}</div>)}
            </div>
          </div>

          <div className="bg-white border border-gray-200 rounded-xl p-5">
            <h3 className="font-semibold text-gray-800 mb-4">Batches</h3>
            <div className="flex flex-col gap-2 mb-4">
              <select className={inp} value={batchDivId} onChange={e => setBatchDivId(e.target.value)}>
                <option value="">Division</option>
                {divisions.map((d: any) => <option key={d.id} value={d.id}>{d.label}</option>)}
              </select>
              <div className="flex gap-2">
                <input className={`${inp} flex-1`} placeholder="Label (A1)" value={batchLabel} onChange={e => setBatchLabel(e.target.value)} />
                <button className={btn} onClick={() => batchMut.mutate()} disabled={!batchDivId || !batchLabel}>+</button>
              </div>
            </div>
            {batchDivId && <div className="flex flex-wrap gap-2">{batchesForDiv.map((b: any) => <span key={b.id} className="bg-indigo-50 text-indigo-700 text-xs font-medium px-2.5 py-1 rounded-full">{b.label}</span>)}</div>}
          </div>
        </div>
      )}

      {/* ── Assignments ── */}
      {tab === 'assignments' && (
        <div>
          <div className="bg-white border border-gray-200 rounded-xl p-5 mb-5 max-w-2xl">
            <h3 className="font-semibold text-gray-800 mb-4 flex items-center gap-2"><Plus size={15} />Assign Teacher to Subject + Division</h3>
            <div className="grid grid-cols-2 gap-3">
              <select className={inp} value={aForm.teacher_user_id} onChange={e => setAForm(f => ({ ...f, teacher_user_id: e.target.value }))}>
                <option value="">Teacher</option>
                {teachers.map((t: any) => <option key={t.id} value={t.id}>{t.full_name} ({t.teacher_id})</option>)}
              </select>
              <select className={inp} value={aForm.subject_id} onChange={e => setAForm(f => ({ ...f, subject_id: e.target.value }))}>
                <option value="">Subject</option>
                {subjects.map((s: any) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}
              </select>
              <select className={inp} value={aForm.division_id} onChange={e => setAForm(f => ({ ...f, division_id: e.target.value, batch_id: '' }))}>
                <option value="">Division</option>
                {divisions.map((d: any) => <option key={d.id} value={d.id}>{d.label}</option>)}
              </select>
              <select className={inp} value={aForm.batch_id} onChange={e => setAForm(f => ({ ...f, batch_id: e.target.value }))} disabled={!aForm.division_id}>
                <option value="">No batch (lecture)</option>
                {batchesForAssign.map((b: any) => <option key={b.id} value={b.id}>{b.label}</option>)}
              </select>
            </div>
            <button className={`${btn} mt-3`} onClick={() => assignMut.mutate()} disabled={!aForm.teacher_user_id || !aForm.subject_id || !aForm.division_id}>Assign</button>
          </div>
          <div className="bg-white border border-gray-200 rounded-xl overflow-hidden">
            <table className="w-full text-sm">
              <thead><tr className="bg-gray-50 border-b border-gray-200">{['Teacher','Subject','Division','Batch',''].map(h=><th key={h} className="px-4 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>)}</tr></thead>
              <tbody className="divide-y divide-gray-100">
                {assignments.map((a: any) => (
                  <tr key={a.id} className="hover:bg-gray-50">
                    <td className="px-4 py-2.5 text-gray-900">{a.teacher_name}</td>
                    <td className="px-4 py-2.5 font-mono text-xs text-gray-600">{a.subject_code}</td>
                    <td className="px-4 py-2.5 text-gray-600">{a.division_label}</td>
                    <td className="px-4 py-2.5">{a.batch_label ? <span className="bg-indigo-50 text-indigo-700 text-xs font-medium px-2 py-0.5 rounded-full">{a.batch_label}</span> : <span className="text-gray-400">—</span>}</td>
                    <td className="px-4 py-2.5"><button onClick={() => delAssignMut.mutate(a.id)} className="text-red-400 hover:text-red-600 transition-colors"><Trash2 size={14} /></button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ── Timetable ── */}
      {tab === 'timetable' && (
        <div>
          {!activeSem
            ? <div className="bg-orange-50 border border-orange-200 text-orange-700 rounded-xl px-4 py-3 text-sm">No active semester. Go to Semesters tab and activate one.</div>
            : <>
              <div className="flex items-center justify-between mb-4">
                <p className="text-sm text-gray-600">Active: <strong>{activeSem.name}</strong></p>
              </div>
              <div className="bg-white border border-gray-200 rounded-xl p-4 mb-5">
                <h3 className="font-semibold text-gray-800 mb-3 flex items-center gap-2"><Plus size={15} />Add Slot</h3>
                <div className="flex gap-3 flex-wrap items-end">
                  <select className={inp} value={slotForm.assignment_id} onChange={e => setSlotForm(f => ({ ...f, assignment_id: e.target.value }))}>
                    <option value="">Assignment</option>
                    {assignments.map((a: any) => <option key={a.id} value={a.id}>{a.teacher_name} · {a.subject_code} · {a.division_label}{a.batch_label ? ` · ${a.batch_label}` : ''}</option>)}
                  </select>
                  <select className={inp} value={slotForm.day_of_week} onChange={e => setSlotForm(f => ({ ...f, day_of_week: e.target.value }))}>
                    {DAYS.map((d, i) => <option key={i} value={i}>{d}</option>)}
                  </select>
                  <select className={inp} value={slotForm.time_start} onChange={e => setSlotForm(f => ({ ...f, time_start: e.target.value }))}>
                    {TIME_SLOTS.map(t => <option key={t} value={t}>{t}</option>)}
                  </select>
                  <input className={`${inp} w-24`} placeholder="Room" value={slotForm.room} onChange={e => setSlotForm(f => ({ ...f, room: e.target.value }))} />
                  <button className={btn} onClick={() => slotMut.mutate()} disabled={!slotForm.assignment_id}>Add</button>
                </div>
              </div>
              <div className="overflow-x-auto rounded-xl border border-gray-200">
                <table className="w-full text-xs border-collapse">
                  <thead>
                    <tr className="bg-gray-50">
                      <th className="px-3 py-2.5 text-left font-semibold text-gray-500 border-b border-r border-gray-200 w-20">Time</th>
                      {DAYS.map(d => <th key={d} className="px-3 py-2.5 text-center font-semibold text-gray-500 border-b border-r border-gray-200 min-w-[120px]">{d}</th>)}
                    </tr>
                  </thead>
                  <tbody>
                    {TIME_SLOTS.map(ts => (
                      <tr key={ts} className="border-b border-gray-100">
                        <td className="px-3 py-2 font-medium text-gray-500 border-r border-gray-200 whitespace-nowrap bg-gray-50">{ts}</td>
                        {DAYS.map((_, di) => {
                          const daySlots = slots.filter((s: any) => s.day_of_week === di && s.time_start === ts)
                          return (
                            <td key={di} className="px-2 py-1.5 border-r border-gray-100 align-top">
                              {daySlots.map((s: any) => (
                                <div key={s.id} className="flex items-center justify-between gap-1 bg-indigo-50 border border-indigo-100 rounded px-1.5 py-1 mb-1">
                                  <div>
                                    <span className="font-semibold text-indigo-700">{s.subject_code}</span>
                                    {s.batch_label && <span className="text-indigo-400 ml-1">({s.batch_label})</span>}
                                    <div className="text-gray-400 truncate max-w-[90px]">{s.teacher_name.split(' ').slice(-1)[0]}</div>
                                  </div>
                                  <button onClick={() => delSlotMut.mutate(s.id)} className="text-red-300 hover:text-red-500 transition-colors shrink-0"><Trash2 size={11} /></button>
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
          }
        </div>
      )}
    </div>
  )
}
