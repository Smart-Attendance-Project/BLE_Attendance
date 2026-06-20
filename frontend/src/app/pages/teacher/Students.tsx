import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { UserPlus } from "lucide-react";
import { addStudent, getMyDivisions, listBatches, getDivisionStudents } from "../../../api/endpoints";
import { Button } from "../../ui/button";
import { PageHeader, Panel, EmptyState, Field } from "../../components/shared/Primitives";
import { StatusChip } from "../../components/shared/StatusChip";

export function Students() {
  const qc = useQueryClient();
  const { data: divisions = [] } = useQuery({ queryKey: ["my-divisions"], queryFn: getMyDivisions });
  const [divId, setDivId] = useState<number | "">("");
  const { data: batches = [] } = useQuery({ queryKey: ["batches", divId], queryFn: () => listBatches(divId as number), enabled: !!divId });
  const { data: students = [] } = useQuery({ queryKey: ["students", divId], queryFn: () => getDivisionStudents(divId as number), enabled: !!divId });
  const [form, setForm] = useState({ full_name: "", student_id: "", batch_id: "" });
  const [err, setErr] = useState("");
  const [showForm, setShowForm] = useState(false);

  const addMut = useMutation({
    mutationFn: () => addStudent({ full_name: form.full_name, student_id: form.student_id, division_id: divId as number, batch_id: form.batch_id ? Number(form.batch_id) : undefined }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["students", divId] });
      setForm({ full_name: "", student_id: "", batch_id: "" });
      setErr("");
      setShowForm(false);
    },
    onError: (e: any) => setErr(e.response?.data?.detail || "Error adding student"),
  });

  return (
    <div className="max-w-5xl">
      <PageHeader
        title="Students"
        subtitle="Select a division, then add and review enrolled students."
      />

      <div className="mb-8 flex flex-wrap items-center gap-4">
        <div className="relative w-64">
          <select
            value={divId}
            onChange={(e) => {
              setDivId(Number(e.target.value));
              setShowForm(false);
            }}
            className="h-11 w-full appearance-none rounded-lg border border-slate-200 bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-1 focus:ring-primary"
          >
            <option value="">Select division</option>
            {(divisions as any[]).map((d) => <option key={d.id} value={d.id}>{d.label}</option>)}
          </select>
          <div className="absolute inset-y-0 right-3 flex items-center pointer-events-none">
            <svg className="h-4 w-4 text-muted-foreground" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path d="M19 9l-7 7-7-7" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" />
            </svg>
          </div>
        </div>

        {divId && (
          <Button onClick={() => setShowForm((v) => !v)} className="rounded-lg">
            <UserPlus className="size-4" /> Add student
          </Button>
        )}
      </div>

      {showForm && divId && (
        <Panel className="mb-6">
          <div className="grid gap-4 md:grid-cols-[1.2fr_1.2fr_0.8fr_auto]">
            <Field label="Full name">
              <input value={form.full_name} onChange={(e) => setForm((f) => ({ ...f, full_name: e.target.value }))} className="h-11 w-full rounded-lg border border-slate-200 bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-1 focus:ring-primary" />
            </Field>
            <Field label="Student ID">
              <input value={form.student_id} onChange={(e) => setForm((f) => ({ ...f, student_id: e.target.value }))} className="h-11 w-full rounded-lg border border-slate-200 bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-1 focus:ring-primary" />
            </Field>
            <Field label="Batch">
              <select value={form.batch_id} onChange={(e) => setForm((f) => ({ ...f, batch_id: e.target.value }))} className="h-11 w-full rounded-lg border border-slate-200 bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-1 focus:ring-primary">
                <option value="">No batch</option>
                {(batches as any[]).map((b) => <option key={b.id} value={b.id}>{b.label}</option>)}
              </select>
            </Field>
            <div className="flex items-end">
              <Button onClick={() => addMut.mutate()} disabled={!form.full_name || !form.student_id} className="h-11 rounded-lg">
                Save
              </Button>
            </div>
          </div>
          {err && <p className="mt-3 text-sm text-red-600">{err}</p>}
        </Panel>
      )}

      {divId ? (
        <Panel className="overflow-hidden p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-sm text-left border-collapse">
              <thead>
                <tr className="bg-slate-50 text-[10px] uppercase tracking-widest font-bold text-muted-foreground border-b border-slate-200">
                  <th className="px-8 py-4 w-1/3">Student ID</th>
                  <th className="px-8 py-4 w-1/2">Name</th>
                  <th className="px-8 py-4 text-right">Batch</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {(students as any[]).length === 0 ? (
                  <tr>
                    <td colSpan={3} className="px-5 py-10">
                      <EmptyState title="No students in this division" description="Add the first student to populate the roster." />
                    </td>
                  </tr>
                ) : (
                  (students as any[]).map((s) => (
                    <tr key={s.id} className="hover:bg-slate-50/80 transition-colors">
                      <td className="px-8 py-4 font-medium text-muted-foreground">{s.student_id}</td>
                      <td className="px-8 py-4 font-medium text-foreground">{s.full_name}</td>
                      <td className="px-8 py-4 text-right">
                        {s.batch_id ? (
                          <StatusChip tone="info">{(batches as any[]).find((b) => b.id === s.batch_id)?.label ?? "Batch"}</StatusChip>
                        ) : (
                          <span className="text-muted-foreground">No batch</span>
                        )}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </Panel>
      ) : (
        <EmptyState title="Choose a division" description="Student management starts with selecting a division." />
      )}
    </div>
  );
}
