import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Trash2 } from "lucide-react";
import {
  listSemesters,
  createSemester,
  activateSemester,
  listBranches,
  createBranch,
  listDivisions,
  createDivision,
  listBatches,
  createBatch,
  listSubjects,
  adminListTeachers,
  listAssignments,
  createAssignment,
  deleteAssignment,
  listSlots,
  createSlot,
  deleteSlot,
} from "../../../api/endpoints";
import { Button } from "../../ui/button";
import { PageHeader, Panel, Field, EmptyState } from "../../components/shared/Primitives";
import { StatusChip } from "../../components/shared/StatusChip";

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const TIME_SLOTS = ["09:10", "10:10", "11:10", "12:10", "13:10", "14:20", "15:20"];
const TIME_ENDS: Record<string, string> = {
  "09:10": "10:10",
  "10:10": "11:10",
  "11:10": "12:10",
  "12:10": "13:10",
  "13:10": "14:10",
  "14:20": "15:20",
  "15:20": "16:20",
};

type Tab = "semesters" | "branches" | "assignments" | "timetable";

export function Schedule() {
  const qc = useQueryClient();
  const [tab, setTab] = useState<Tab>("semesters");

  const { data: semesters = [] } = useQuery({ queryKey: ["semesters"], queryFn: listSemesters });
  const { data: branches = [] } = useQuery({ queryKey: ["branches"], queryFn: listBranches });
  const { data: divisions = [] } = useQuery({ queryKey: ["divisions"], queryFn: listDivisions });
  const { data: subjects = [] } = useQuery({ queryKey: ["subjects"], queryFn: listSubjects });
  const { data: teachers = [] } = useQuery({ queryKey: ["teachers"], queryFn: adminListTeachers });
  const { data: assignments = [] } = useQuery({ queryKey: ["assignments"], queryFn: listAssignments });

  const activeSem = (semesters as any[]).find((s) => s.is_active);
  const { data: slots = [] } = useQuery({
    queryKey: ["slots", activeSem?.id],
    queryFn: () => listSlots({ semester_id: activeSem?.id }),
    enabled: !!activeSem,
  });

  const [semForm, setSemForm] = useState({ name: "", start_date: "", end_date: "", is_active: false });
  const semMut = useMutation({ mutationFn: () => createSemester(semForm), onSuccess: () => { qc.invalidateQueries({ queryKey: ["semesters"] }); setSemForm({ name: "", start_date: "", end_date: "", is_active: false }); } });
  const activateMut = useMutation({ mutationFn: (id: number) => activateSemester(id), onSuccess: () => qc.invalidateQueries({ queryKey: ["semesters"] }) });

  const [branchForm, setBranchForm] = useState({ code: "", name: "" });
  const branchMut = useMutation({ mutationFn: () => createBranch(branchForm), onSuccess: () => { qc.invalidateQueries({ queryKey: ["branches"] }); setBranchForm({ code: "", name: "" }); } });

  const [divForm, setDivForm] = useState({ branch_id: "", year: "1", div_number: "1", label: "" });
  const divMut = useMutation({
    mutationFn: () => createDivision({ branch_id: Number(divForm.branch_id), year: Number(divForm.year), div_number: Number(divForm.div_number), label: divForm.label }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["divisions"] }); setDivForm({ branch_id: "", year: "1", div_number: "1", label: "" }); },
  });

  const [batchDivId, setBatchDivId] = useState("");
  const { data: batchesForDiv = [] } = useQuery({ queryKey: ["batches", batchDivId], queryFn: () => listBatches(Number(batchDivId)), enabled: !!batchDivId });
  const [batchLabel, setBatchLabel] = useState("");
  const batchMut = useMutation({ mutationFn: () => createBatch({ division_id: Number(batchDivId), label: batchLabel }), onSuccess: () => { qc.invalidateQueries({ queryKey: ["batches", batchDivId] }); setBatchLabel(""); } });

  const [aForm, setAForm] = useState({ teacher_user_id: "", subject_id: "", division_id: "", batch_id: "" });
  const { data: batchesForAssign = [] } = useQuery({ queryKey: ["batches", aForm.division_id], queryFn: () => listBatches(Number(aForm.division_id)), enabled: !!aForm.division_id });
  const assignMut = useMutation({
    mutationFn: () => createAssignment({ teacher_user_id: aForm.teacher_user_id, subject_id: Number(aForm.subject_id), division_id: Number(aForm.division_id), batch_id: aForm.batch_id ? Number(aForm.batch_id) : undefined }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["assignments"] }); setAForm({ teacher_user_id: "", subject_id: "", division_id: "", batch_id: "" }); },
  });
  const delAssignMut = useMutation({ mutationFn: (id: number) => deleteAssignment(id), onSuccess: () => qc.invalidateQueries({ queryKey: ["assignments"] }) });

  const [slotForm, setSlotForm] = useState({ assignment_id: "", day_of_week: "0", time_start: "09:10", room: "" });
  const slotMut = useMutation({
    mutationFn: () => createSlot({ assignment_id: Number(slotForm.assignment_id), semester_id: activeSem?.id, day_of_week: Number(slotForm.day_of_week), time_start: slotForm.time_start, time_end: TIME_ENDS[slotForm.time_start] || "10:10", room: slotForm.room }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["slots", activeSem?.id] }); setSlotForm({ assignment_id: "", day_of_week: "0", time_start: "09:10", room: "" }); },
  });
  const delSlotMut = useMutation({ mutationFn: (id: number) => deleteSlot(id), onSuccess: () => qc.invalidateQueries({ queryKey: ["slots", activeSem?.id] }) });

  const tabs: { key: Tab; label: string }[] = [
    { key: "semesters", label: "Semesters" },
    { key: "branches", label: "Branches & Divisions" },
    { key: "assignments", label: "Assignments" },
    { key: "timetable", label: "Timetable" },
  ];

  const slotsByCell = useMemo(() => {
    const map = new Map<string, any[]>();
    (slots as any[]).forEach((s) => {
      const key = `${s.day_of_week}-${s.time_start}`;
      map.set(key, [...(map.get(key) ?? []), s]);
    });
    return map;
  }, [slots]);

  return (
    <div className="max-w-6xl">
      <PageHeader title="Schedule Management" subtitle="Semesters, branches, assignments, and timetable in one place." />

      <div className="mb-8 flex gap-1 overflow-x-auto border-b border-border">
        {tabs.map((t) => (
          <button key={t.key} onClick={() => setTab(t.key)} className={`whitespace-nowrap border-b-2 px-4 py-3 text-sm font-medium transition-colors ${tab === t.key ? "border-foreground text-foreground" : "border-transparent text-muted-foreground hover:text-foreground"}`}>
            {t.label}
          </button>
        ))}
      </div>

      {tab === "semesters" && (
        <div className="max-w-2xl space-y-6">
          <Panel>
            <div className="grid gap-4">
              <Field label="Semester name">
                <input value={semForm.name} onChange={(e) => setSemForm((f) => ({ ...f, name: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" />
              </Field>
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="Start date"><input type="date" value={semForm.start_date} onChange={(e) => setSemForm((f) => ({ ...f, start_date: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" /></Field>
                <Field label="End date"><input type="date" value={semForm.end_date} onChange={(e) => setSemForm((f) => ({ ...f, end_date: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" /></Field>
              </div>
              <label className="flex items-center gap-2 text-sm text-muted-foreground">
                <input type="checkbox" checked={semForm.is_active} onChange={(e) => setSemForm((f) => ({ ...f, is_active: e.target.checked }))} />
                Set as active semester
              </label>
              <Button onClick={() => semMut.mutate()} disabled={!semForm.name} className="h-11 rounded-xl w-fit">Add Semester</Button>
            </div>
          </Panel>

          <Panel className="overflow-hidden p-0">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-surface-2/70 text-left text-xs uppercase tracking-[0.08em] text-muted-foreground">
                  <tr>
                    <th className="px-5 py-4">Name</th>
                    <th className="px-5 py-4">Start</th>
                    <th className="px-5 py-4">End</th>
                    <th className="px-5 py-4">Status</th>
                    <th className="px-5 py-4" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {(semesters as any[]).map((s) => (
                    <tr key={s.id} className="hover:bg-surface-2/40">
                      <td className="px-5 py-4">{s.name}</td>
                      <td className="px-5 py-4 text-muted-foreground">{s.start_date}</td>
                      <td className="px-5 py-4 text-muted-foreground">{s.end_date}</td>
                      <td className="px-5 py-4">{s.is_active ? <StatusChip tone="active">Active</StatusChip> : <StatusChip tone="neutral">Inactive</StatusChip>}</td>
                      <td className="px-5 py-4 text-right">{!s.is_active && <button onClick={() => activateMut.mutate(s.id)} className="text-sm font-medium text-[#404a43] hover:underline">Activate</button>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Panel>
        </div>
      )}

      {tab === "branches" && (
        <div className="grid gap-6 lg:grid-cols-3">
          <Panel title="Branches">
            <div className="grid gap-3">
              <Field label="Code"><input value={branchForm.code} onChange={(e) => setBranchForm((f) => ({ ...f, code: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" /></Field>
              <Field label="Name"><input value={branchForm.name} onChange={(e) => setBranchForm((f) => ({ ...f, name: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" /></Field>
              <Button onClick={() => branchMut.mutate()} disabled={!branchForm.code || !branchForm.name} className="h-11 rounded-xl w-fit">Add Branch</Button>
            </div>
            <div className="mt-5 space-y-2">
              {(branches as any[]).map((b) => (
                <div key={b.id} className="flex items-center justify-between rounded-xl bg-surface-2/60 px-3 py-2">
                  <span className="font-mono text-xs text-muted-foreground">{b.code}</span>
                  <span className="text-sm">{b.name}</span>
                </div>
              ))}
            </div>
          </Panel>

          <Panel title="Divisions">
            <div className="grid gap-3">
              <Field label="Branch">
                <select value={divForm.branch_id} onChange={(e) => setDivForm((f) => ({ ...f, branch_id: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15">
                  <option value="">Select branch</option>
                  {(branches as any[]).map((b) => <option key={b.id} value={b.id}>{b.code} — {b.name}</option>)}
                </select>
              </Field>
              <div className="grid gap-3 sm:grid-cols-2">
                <Field label="Year">
                  <select value={divForm.year} onChange={(e) => setDivForm((f) => ({ ...f, year: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15">
                    {[1, 2, 3, 4].map((y) => <option key={y} value={y}>Year {y}</option>)}
                  </select>
                </Field>
                <Field label="Division #">
                  <input value={divForm.div_number} onChange={(e) => setDivForm((f) => ({ ...f, div_number: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" />
                </Field>
              </div>
              <Field label="Label"><input value={divForm.label} onChange={(e) => setDivForm((f) => ({ ...f, label: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" /></Field>
              <Button onClick={() => divMut.mutate()} disabled={!divForm.branch_id || !divForm.label} className="h-11 rounded-xl w-fit">Add Division</Button>
            </div>
            <div className="mt-5 space-y-2">
              {(divisions as any[]).map((d) => (
                <div key={d.id} className="flex items-center justify-between rounded-xl bg-surface-2/60 px-3 py-2">
                  <span className="text-sm">{d.label}</span>
                  <span className="text-xs text-muted-foreground">Year {d.year}</span>
                </div>
              ))}
            </div>
          </Panel>

          <Panel title="Batches">
            <div className="grid gap-3">
              <Field label="Division">
                <select value={batchDivId} onChange={(e) => setBatchDivId(e.target.value)} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15">
                  <option value="">Select division</option>
                  {(divisions as any[]).map((d) => <option key={d.id} value={d.id}>{d.label}</option>)}
                </select>
              </Field>
              <Field label="Batch label">
                <input value={batchLabel} onChange={(e) => setBatchLabel(e.target.value)} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" />
              </Field>
              <Button onClick={() => batchMut.mutate()} disabled={!batchDivId || !batchLabel} className="h-11 rounded-xl w-fit">Add Batch</Button>
            </div>
            <div className="mt-5 flex flex-wrap gap-2">
              {(batchDivId ? (batchesForDiv as any[]) : []).map((b) => <StatusChip key={b.id} tone="info">{b.label}</StatusChip>)}
            </div>
          </Panel>
        </div>
      )}

      {tab === "assignments" && (
        <div className="grid gap-6 lg:grid-cols-[1fr_1.1fr]">
          <Panel title="Create assignment" className="h-fit">
            <div className="grid gap-4">
              <Field label="Teacher">
                <select value={aForm.teacher_user_id} onChange={(e) => setAForm((f) => ({ ...f, teacher_user_id: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15">
                  <option value="">Select teacher</option>
                  {(teachers as any[]).map((t) => <option key={t.id} value={t.id}>{t.full_name} ({t.teacher_id})</option>)}
                </select>
              </Field>
              <Field label="Subject">
                <select value={aForm.subject_id} onChange={(e) => setAForm((f) => ({ ...f, subject_id: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15">
                  <option value="">Select subject</option>
                  {(subjects as any[]).map((s) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}
                </select>
              </Field>
              <Field label="Division">
                <select value={aForm.division_id} onChange={(e) => setAForm((f) => ({ ...f, division_id: e.target.value, batch_id: "" }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15">
                  <option value="">Select division</option>
                  {(divisions as any[]).map((d) => <option key={d.id} value={d.id}>{d.label}</option>)}
                </select>
              </Field>
              <Field label="Batch">
                <select value={aForm.batch_id} onChange={(e) => setAForm((f) => ({ ...f, batch_id: e.target.value }))} disabled={!aForm.division_id} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15">
                  <option value="">Lecture / no batch</option>
                  {(batchesForAssign as any[]).map((b) => <option key={b.id} value={b.id}>{b.label}</option>)}
                </select>
              </Field>
              <Button onClick={() => assignMut.mutate()} disabled={!aForm.teacher_user_id || !aForm.subject_id || !aForm.division_id} className="h-11 rounded-xl w-fit">Assign</Button>
            </div>
          </Panel>

          <Panel className="overflow-hidden p-0">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-surface-2/70 text-left text-xs uppercase tracking-[0.08em] text-muted-foreground">
                  <tr>
                    <th className="px-5 py-4">Teacher</th>
                    <th className="px-5 py-4">Subject</th>
                    <th className="px-5 py-4">Division</th>
                    <th className="px-5 py-4">Batch</th>
                    <th className="px-5 py-4" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {(assignments as any[]).map((a) => (
                    <tr key={a.id} className="hover:bg-surface-2/40">
                      <td className="px-5 py-4">{a.teacher_name}</td>
                      <td className="px-5 py-4 font-mono text-muted-foreground">{a.subject_code}</td>
                      <td className="px-5 py-4">{a.division_label}</td>
                      <td className="px-5 py-4">{a.batch_label ? <StatusChip tone="info">{a.batch_label}</StatusChip> : <span className="text-muted-foreground">Lecture</span>}</td>
                      <td className="px-5 py-4 text-right"><button onClick={() => delAssignMut.mutate(a.id)} className="text-muted-foreground hover:text-[#a85a4c]"><Trash2 className="size-4" /></button></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Panel>
        </div>
      )}

      {tab === "timetable" && (
        <div className="grid gap-6">
          {!activeSem ? (
            <EmptyState title="No active semester" description="Activate a semester first, then add timetable slots." />
          ) : (
            <>
              <Panel title="Add slot">
                <div className="grid gap-4 md:grid-cols-[1.5fr_0.6fr_0.6fr_0.8fr_auto]">
                  <Field label="Assignment">
                    <select value={slotForm.assignment_id} onChange={(e) => setSlotForm((f) => ({ ...f, assignment_id: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15">
                      <option value="">Select assignment</option>
                      {(assignments as any[]).map((a) => <option key={a.id} value={a.id}>{a.teacher_name} / {a.subject_code} / {a.division_label}{a.batch_label ? ` / ${a.batch_label}` : ""}</option>)}
                    </select>
                  </Field>
                  <Field label="Day">
                    <select value={slotForm.day_of_week} onChange={(e) => setSlotForm((f) => ({ ...f, day_of_week: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15">
                      {DAYS.map((d, i) => <option key={d} value={i}>{d}</option>)}
                    </select>
                  </Field>
                  <Field label="Start">
                    <select value={slotForm.time_start} onChange={(e) => setSlotForm((f) => ({ ...f, time_start: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15">
                      {TIME_SLOTS.map((t) => <option key={t} value={t}>{t}</option>)}
                    </select>
                  </Field>
                  <Field label="Room">
                    <input value={slotForm.room} onChange={(e) => setSlotForm((f) => ({ ...f, room: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" />
                  </Field>
                  <div className="flex items-end">
                    <Button onClick={() => slotMut.mutate()} disabled={!slotForm.assignment_id} className="h-11 rounded-xl">Add</Button>
                  </div>
                </div>
              </Panel>

              <Panel className="overflow-hidden p-0">
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[760px] text-sm">
                    <thead className="bg-foreground text-left text-xs uppercase tracking-[0.08em] text-white/85">
                      <tr>
                        <th className="w-20 px-4 py-3">Time</th>
                        {DAYS.map((d) => <th key={d} className="min-w-[130px] px-3 py-3 text-center">{d}</th>)}
                      </tr>
                    </thead>
                    <tbody>
                      {TIME_SLOTS.map((ts) => (
                        <tr key={ts} className="border-b border-border">
                          <td className="border-r border-border bg-surface-2/60 px-4 py-2 font-medium text-muted-foreground">{ts}</td>
                          {DAYS.map((_, di) => {
                            const daySlots = slotsByCell.get(`${di}-${ts}`) ?? [];
                            return (
                              <td key={di} className="border-r border-border px-2 py-1.5 align-top">
                                {daySlots.map((s) => (
                                  <div key={s.id} className="mb-1 flex items-center justify-between gap-1 rounded-xl border border-border bg-surface-2/70 px-2 py-1.5">
                                    <div>
                                      <span className="text-xs font-medium text-[#404a43]">{s.subject_code}</span>
                                      {s.batch_label && <span className="ml-1 text-xs text-muted-foreground">({s.batch_label})</span>}
                                      {s.room && <div className="text-[11px] text-muted-foreground">{s.room}</div>}
                                    </div>
                                    <button onClick={() => delSlotMut.mutate(s.id)} className="text-muted-foreground hover:text-[#a85a4c]"><Trash2 className="size-3.5" /></button>
                                  </div>
                                ))}
                              </td>
                            );
                          })}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </Panel>
            </>
          )}
        </div>
      )}
    </div>
  );
}
