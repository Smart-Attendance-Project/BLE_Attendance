import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Trash2 } from 'lucide-react'
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

const inp = "border-2 border-black rounded-lg px-4 py-3 text-base focus:outline-none focus:ring-2 focus:ring-indigo-400 shadow-[2px_2px_0_0_#000] bg-white"
const btn = "bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 text-white text-base font-bold px-5 py-3 rounded-lg border-2 border-black shadow-[3px_3px_0_0_#000] transition-all"

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

  const [semForm, setSemForm] = useState({ name: '', start_date: '', end_date: '', is_active: false })
  const semMut = useMutation({ mutationFn: () => createSemester(semForm), onSuccess: () => { qc.invalidateQueries({ queryKey: ['semesters'] }); setSemForm({ name: '', start_date: '', end_date: '', is_active: false }) } })
  const activateMut = useMutation({ mutationFn: (id: number) => activateSemester(id), onSuccess: () => qc.invalidateQueries({ queryKey: ['semesters'] }) })

  const [branchForm, setBranchForm] = useState({ code: '', name: '' })
  const branchMut = useMutation({ mutationFn: () => createBranch(branchForm), onSuccess: () => { qc.invalidateQueries({ queryKey: ['branches'] }); setBranchForm({ code: '', name: '' }) } })

  const [divForm, setDivForm] = useState({ branch_id: '', year: '1', div_number: '1', label: '' })
  const divMut = useMutation({
    mutationFn: () => createDivision({ branch_id: Number(divForm.branch_id), year: Number(divForm.year), div_number: Number(divForm.div_number), label: divForm.label }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['divisions'] }); setDivForm({ branch_id: '', year: '1', div_number: '1', label: '' }) },
  })

  const [batchDivId, setBatchDivId] = useState('')
  const { data: batchesForDiv = [] } = useQuery({ queryKey: ['batches', batchDivId], queryFn: () => listBatches(Number(batchDivId)), enabled: !!batchDivId })
  const [batchLabel, setBatchLabel] = useState('')
  const batchMut = useMutation({ mutationFn: () => createBatch({ division_id: Number(batchDivId), label: batchLabel }), onSuccess: () => { qc.invalidateQueries({ queryKey: ['batches', batchDivId] }); setBatchLabel('') } })

  const [aForm, setAForm] = useState({ teacher_user_id: '', subject_id: '', division_id: '', batch_id: '' })
  const { data: batchesForAssign = [] } = useQuery({ queryKey: ['batches', aForm.division_id], queryFn: () => listBatches(Number(aForm.division_id)), enabled: !!aForm.division_id })
  const assignMut = useMutation({
    mutationFn: () => createAssignment({ teacher_user_id: aForm.teacher_user_id, subject_id: Number(aForm.subject_id), division_id: Number(aForm.division_id), batch_id: aForm.batch_id ? Number(aForm.batch_id) : undefined }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['assignments'] }); setAForm({ teacher_user_id: '', subject_id: '', division_id: '', batch_id: '' }) },
  })
  const delAssignMut = useMutation({ mutationFn: (id: number) => deleteAssignment(id), onSuccess: () => qc.invalidateQueries({ queryKey: ['assignments'] }) })

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
    <div className="p-8 max-w-6xl mx-auto">
      <h1 className="text-3xl font-black text-zinc-900 mb-6">Schedule Management</h1>

      <div className="flex gap-1 mb-8 border-b-2 border-black">
        {tabs.map(t => (
          <button key={t.key} onClick={() => setTab(t.key)}
            className={`px-5 py-3 text-base font-bold border-b-4 transition-colors -mb-0.5 ${tab === t.key ? 'border-black text-zinc-900' : 'border-transparent text-zinc-400 hover:text-zinc-700'}`}>
            {t.label}
          </button>
        ))}
      </div>

      {/* Semesters */}
      {tab === 'semesters' && (
        <div className="max-w-2xl">
          <div className="bg-zinc-50 border-2 border-black rounded-xl p-6 mb-6 shadow-[4px_4px_0_0_#000]">
            <h3 className="font-black text-zinc-800 text-lg mb-4">Add Semester</h3>
            <div className="flex flex-col gap-4">
              <input className={inp} placeholder="Name (e.g. Sem II 2025-26)" value={semForm.name} onChange={e => setSemForm(f => ({ ...f, name: e.target.value }))} />
              <div className="flex gap-4">
                <input type="date" className={`${inp} flex-1`} value={semForm.start_date} onChange={e => setSemForm(f => ({ ...f, start_date: e.target.value }))} />
                <input type="date" className={`${inp} flex-1`} value={semForm.end_date} onChange={e => setSemForm(f => ({ ...f, end_date: e.target.value }))} />
              </div>
              <div className="flex items-center justify-between">
                <label className="flex items-center gap-2 text-base text-zinc-700 cursor-pointer font-medium">
                  <input type="checkbox" checked={semForm.is_active} onChange={e => setSemForm(f => ({ ...f, is_active: e.target.checked }))} className="w-4 h-4" />
                  Set as active semester
                </label>
                <button className={btn} onClick={() => semMut.mutate()} disabled={!semForm.name}>Add</button>
              </div>
            </div>
          </div>
          <div className="bg-zinc-50 border-2 border-black rounded-xl overflow-hidden shadow-[4px_4px_0_0_#000]">
            <table className="w-full text-base">
              <thead><tr className="bg-zinc-900 text-white">{['Name','Start','End','Status',''].map(h=><th key={h} className="px-5 py-4 text-left text-sm font-bold uppercase tracking-wider">{h}</th>)}</tr></thead>
              <tbody className="divide-y divide-zinc-200">
                {semesters.map((s: any) => (
                  <tr key={s.id} className="hover:bg-zinc-100">
                    <td className="px-5 py-3.5 font-semibold text-zinc-900">{s.name}</td>
                    <td className="px-5 py-3.5 text-zinc-600">{s.start_date}</td>
                    <td className="px-5 py-3.5 text-zinc-600">{s.end_date}</td>
                    <td className="px-5 py-3.5">{s.is_active ? <span className="bg-indigo-100 border-2 border-black text-indigo-900 text-sm font-bold px-3 py-1 rounded-lg">Active</span> : <span className="text-zinc-400 text-sm">Inactive</span>}</td>
                    <td className="px-5 py-3.5">{!s.is_active && <button onClick={() => activateMut.mutate(s.id)} className="text-sm font-bold text-indigo-600 hover:underline">Activate</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Branches & Divisions */}
      {tab === 'branches' && (
        <div className="flex flex-col gap-6 max-w-2xl">
          {/* Branches */}
          <div className="bg-zinc-50 border-2 border-black rounded-xl p-6 shadow-[4px_4px_0_0_#000]">
            <h3 className="font-black text-zinc-800 text-lg mb-4">Branches</h3>
            <div className="flex flex-col gap-3 mb-5">
              <div className="flex gap-3">
                <input className={`${inp} w-28`} placeholder="Code (CE)" value={branchForm.code} onChange={e => setBranchForm(f => ({ ...f, code: e.target.value }))} />
                <input className={`${inp} flex-1`} placeholder="Full name" value={branchForm.name} onChange={e => setBranchForm(f => ({ ...f, name: e.target.value }))} />
              </div>
              <button className={`${btn} self-start`} onClick={() => branchMut.mutate()} disabled={!branchForm.code || !branchForm.name}>Add Branch</button>
            </div>
            <div className="flex flex-col divide-y divide-zinc-200">
              {branches.map((b: any) => (
                <div key={b.id} className="flex items-center gap-4 py-2.5">
                  <span className="font-mono text-sm text-zinc-400 w-14">{b.code}</span>
                  <span className="text-zinc-800 font-medium">{b.name}</span>
                </div>
              ))}
            </div>
          </div>

          {/* Divisions */}
          <div className="bg-zinc-50 border-2 border-black rounded-xl p-6 shadow-[4px_4px_0_0_#000]">
            <h3 className="font-black text-zinc-800 text-lg mb-4">Divisions</h3>
            <div className="flex flex-col gap-3 mb-5">
              <select className={inp} value={divForm.branch_id} onChange={e => setDivForm(f => ({ ...f, branch_id: e.target.value }))}>
                <option value="">Select branch</option>
                {branches.map((b: any) => <option key={b.id} value={b.id}>{b.code} — {b.name}</option>)}
              </select>
              <div className="flex gap-3">
                <select className={`${inp} flex-1`} value={divForm.year} onChange={e => setDivForm(f => ({ ...f, year: e.target.value }))}>
                  {[1,2,3,4].map(y => <option key={y} value={y}>Year {y}</option>)}
                </select>
                <input className={`${inp} w-28`} placeholder="Div # (1)" value={divForm.div_number} onChange={e => setDivForm(f => ({ ...f, div_number: e.target.value }))} />
              </div>
              <div className="flex gap-3">
                <input className={`${inp} flex-1`} placeholder="Label (e.g. CE-FY-Div1)" value={divForm.label} onChange={e => setDivForm(f => ({ ...f, label: e.target.value }))} />
                <button className={btn} onClick={() => divMut.mutate()} disabled={!divForm.branch_id || !divForm.label}>Add</button>
              </div>
            </div>
            <div className="flex flex-col divide-y divide-zinc-200">
              {divisions.map((d: any) => (
                <div key={d.id} className="flex items-center gap-4 py-2.5">
                  <span className="font-mono text-sm text-zinc-400 w-14">{d.branch_code}</span>
                  <span className="text-zinc-800 font-medium">{d.label}</span>
                  <span className="text-zinc-400 text-sm ml-auto">Year {d.year}</span>
                </div>
              ))}
            </div>
          </div>

          {/* Batches */}
          <div className="bg-zinc-50 border-2 border-black rounded-xl p-6 shadow-[4px_4px_0_0_#000]">
            <h3 className="font-black text-zinc-800 text-lg mb-4">Batches</h3>
            <div className="flex flex-col gap-3 mb-5">
              <select className={inp} value={batchDivId} onChange={e => setBatchDivId(e.target.value)}>
                <option value="">Select division</option>
                {divisions.map((d: any) => <option key={d.id} value={d.id}>{d.label}</option>)}
              </select>
              <div className="flex gap-3">
                <input className={`${inp} flex-1`} placeholder="Batch label (A1)" value={batchLabel} onChange={e => setBatchLabel(e.target.value)} />
                <button className={btn} onClick={() => batchMut.mutate()} disabled={!batchDivId || !batchLabel}>Add</button>
              </div>
            </div>
            {batchDivId && (
              <div className="flex flex-wrap gap-2">
                {batchesForDiv.map((b: any) => (
                  <span key={b.id} className="bg-indigo-100 border-2 border-black text-indigo-900 text-sm font-bold px-3 py-1.5 rounded-lg">{b.label}</span>
                ))}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Assignments */}
      {tab === 'assignments' && (
        <div>
          <div className="bg-zinc-50 border-2 border-black rounded-xl p-6 mb-6 shadow-[4px_4px_0_0_#000] max-w-2xl">
            <h3 className="font-black text-zinc-800 text-lg mb-4">Assign Teacher to Subject + Division</h3>
            <div className="grid grid-cols-2 gap-4">
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
            <button className={`${btn} mt-4`} onClick={() => assignMut.mutate()} disabled={!aForm.teacher_user_id || !aForm.subject_id || !aForm.division_id}>Assign</button>
          </div>
          <div className="bg-zinc-50 border-2 border-black rounded-xl overflow-hidden shadow-[4px_4px_0_0_#000]">
            <table className="w-full text-base">
              <thead><tr className="bg-zinc-900 text-white">{['Teacher','Subject','Division','Batch',''].map(h=><th key={h} className="px-5 py-4 text-left text-sm font-bold uppercase tracking-wider">{h}</th>)}</tr></thead>
              <tbody className="divide-y divide-zinc-200">
                {assignments.map((a: any) => (
                  <tr key={a.id} className="hover:bg-zinc-100">
                    <td className="px-5 py-3.5 font-semibold text-zinc-900">{a.teacher_name}</td>
                    <td className="px-5 py-3.5 font-mono text-sm text-zinc-500">{a.subject_code}</td>
                    <td className="px-5 py-3.5 text-zinc-700">{a.division_label}</td>
                    <td className="px-5 py-3.5">{a.batch_label ? <span className="bg-indigo-100 border-2 border-black text-indigo-900 text-sm font-bold px-3 py-1 rounded-lg">{a.batch_label}</span> : <span className="text-zinc-400">Lecture</span>}</td>
                    <td className="px-5 py-3.5"><button onClick={() => delAssignMut.mutate(a.id)} className="text-zinc-400 hover:text-red-600 transition-colors"><Trash2 size={16} /></button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Timetable */}
      {tab === 'timetable' && (
        <div>
          {!activeSem
            ? <div className="bg-indigo-50 border-2 border-black text-indigo-900 rounded-xl px-5 py-4 text-base font-medium">No active semester. Go to Semesters tab and activate one.</div>
            : <>
              <p className="text-base text-zinc-600 mb-5 font-medium">Active semester: <strong>{activeSem.name}</strong></p>
              <div className="bg-zinc-50 border-2 border-black rounded-xl p-6 mb-6 shadow-[4px_4px_0_0_#000]">
                <h3 className="font-black text-zinc-800 text-lg mb-4">Add Slot</h3>
                <div className="flex gap-4 flex-wrap items-end">
                  <select className={`${inp} flex-1 min-w-64`} value={slotForm.assignment_id} onChange={e => setSlotForm(f => ({ ...f, assignment_id: e.target.value }))}>
                    <option value="">Assignment</option>
                    {assignments.map((a: any) => <option key={a.id} value={a.id}>{a.teacher_name} / {a.subject_code} / {a.division_label}{a.batch_label ? ` / ${a.batch_label}` : ''}</option>)}
                  </select>
                  <select className={`${inp} w-28`} value={slotForm.day_of_week} onChange={e => setSlotForm(f => ({ ...f, day_of_week: e.target.value }))}>
                    {DAYS.map((d, i) => <option key={i} value={i}>{d}</option>)}
                  </select>
                  <select className={`${inp} w-28`} value={slotForm.time_start} onChange={e => setSlotForm(f => ({ ...f, time_start: e.target.value }))}>
                    {TIME_SLOTS.map(t => <option key={t} value={t}>{t}</option>)}
                  </select>
                  <input className={`${inp} w-28`} placeholder="Room" value={slotForm.room} onChange={e => setSlotForm(f => ({ ...f, room: e.target.value }))} />
                  <button className={btn} onClick={() => slotMut.mutate()} disabled={!slotForm.assignment_id}>Add</button>
                </div>
              </div>
              <div className="overflow-x-auto rounded-xl border-2 border-black shadow-[4px_4px_0_0_#000]">
                <table className="w-full text-sm border-collapse">
                  <thead>
                    <tr className="bg-zinc-900 text-white">
                      <th className="px-4 py-3 text-left font-bold border-r border-zinc-700 w-20">Time</th>
                      {DAYS.map(d => <th key={d} className="px-3 py-3 text-center font-bold border-r border-zinc-700 min-w-[130px]">{d}</th>)}
                    </tr>
                  </thead>
                  <tbody>
                    {TIME_SLOTS.map(ts => (
                      <tr key={ts} className="border-b border-zinc-200">
                        <td className="px-4 py-2 font-bold text-zinc-500 border-r border-zinc-200 whitespace-nowrap bg-zinc-50 text-sm">{ts}</td>
                        {DAYS.map((_, di) => {
                          const daySlots = slots.filter((s: any) => s.day_of_week === di && s.time_start === ts)
                          return (
                            <td key={di} className="px-2 py-1.5 border-r border-zinc-100 align-top">
                              {daySlots.map((s: any) => (
                                <div key={s.id} className="flex items-center justify-between gap-1 bg-indigo-50 border border-indigo-200 rounded-lg px-2 py-1.5 mb-1">
                                  <div>
                                    <span className="font-bold text-indigo-800 text-xs">{s.subject_code}</span>
                                    {s.batch_label && <span className="text-indigo-400 text-xs ml-1">({s.batch_label})</span>}
                                    <div className="text-zinc-400 text-xs truncate max-w-[90px]">{s.teacher_name.split(' ').slice(-1)[0]}</div>
                                  </div>
                                  <button onClick={() => delSlotMut.mutate(s.id)} className="text-zinc-300 hover:text-red-500 transition-colors shrink-0"><Trash2 size={12} /></button>
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
