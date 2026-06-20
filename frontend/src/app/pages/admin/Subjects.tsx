import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { listSubjects, createSubject } from "../../../api/endpoints";
import { Button } from "../../ui/button";
import { PageHeader, Panel, Field, EmptyState } from "../../components/shared/Primitives";
import { StatusChip } from "../../components/shared/StatusChip";

export function Subjects() {
  const qc = useQueryClient();
  const { data: subjects = [] } = useQuery({ queryKey: ["subjects"], queryFn: listSubjects });
  const [form, setForm] = useState({ code: "", name: "", subject_type: "lecture" });
  const [err, setErr] = useState("");

  const mut = useMutation({
    mutationFn: () => createSubject(form),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["subjects"] });
      setForm({ code: "", name: "", subject_type: "lecture" });
      setErr("");
    },
    onError: (e: any) => setErr(e.response?.data?.detail || "Error"),
  });

  return (
    <div className="max-w-5xl">
      <PageHeader title="Subjects" subtitle="Maintain the course catalog used in assignments and timetable slots." />

      <Panel className="mb-8">
        <div className="grid gap-4 md:grid-cols-[0.9fr_1.3fr_0.7fr_auto]">
          <Field label="Code">
            <input value={form.code} onChange={(e) => setForm((f) => ({ ...f, code: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" />
          </Field>
          <Field label="Name">
            <input value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" />
          </Field>
          <Field label="Type">
            <select value={form.subject_type} onChange={(e) => setForm((f) => ({ ...f, subject_type: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15">
              <option value="lecture">Lecture</option>
              <option value="lab">Lab</option>
            </select>
          </Field>
          <div className="flex items-end">
            <Button onClick={() => mut.mutate()} disabled={!form.code || !form.name} className="h-11 rounded-xl">
              Add
            </Button>
          </div>
        </div>
        {err && <p className="mt-3 text-sm text-[#a85a4c]">{err}</p>}
      </Panel>

      <Panel className="overflow-hidden p-0">
        {(subjects as any[]).length === 0 ? (
          <div className="p-5">
            <EmptyState title="No subjects yet" description="Create the first subject to start building assignments." />
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-surface-2/70 text-left text-xs uppercase tracking-[0.08em] text-muted-foreground">
                <tr>
                  <th className="px-5 py-4">Code</th>
                  <th className="px-5 py-4">Name</th>
                  <th className="px-5 py-4">Type</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {(subjects as any[]).map((s) => (
                  <tr key={s.id} className="hover:bg-surface-2/40">
                    <td className="px-5 py-4 font-mono text-muted-foreground">{s.code}</td>
                    <td className="px-5 py-4">{s.name}</td>
                    <td className="px-5 py-4">{s.subject_type === "lab" ? <StatusChip tone="lab">Lab</StatusChip> : <StatusChip tone="lecture">Lecture</StatusChip>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Panel>
    </div>
  );
}
