import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { adminListTeachers, adminCreateTeacher } from "../../../api/endpoints";
import { Button } from "../../ui/button";
import { PageHeader, Panel, Field, EmptyState } from "../../components/shared/Primitives";

export function Teachers() {
  const qc = useQueryClient();
  const { data: teachers = [] } = useQuery({ queryKey: ["teachers"], queryFn: adminListTeachers });
  const [form, setForm] = useState({ full_name: "", teacher_id: "", password: "Pass@123" });
  const [err, setErr] = useState("");

  const mut = useMutation({
    mutationFn: () => adminCreateTeacher(form),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["teachers"] });
      setForm({ full_name: "", teacher_id: "", password: "Pass@123" });
      setErr("");
    },
    onError: (e: any) => setErr(e.response?.data?.detail || "Error"),
  });

  return (
    <div className="max-w-5xl">
      <PageHeader title="Teachers" subtitle="Create and review teacher accounts." />

      <Panel className="mb-8">
        <div className="grid gap-4 md:grid-cols-[1.1fr_0.8fr_0.8fr_auto]">
          <Field label="Full name">
            <input value={form.full_name} onChange={(e) => setForm((f) => ({ ...f, full_name: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" />
          </Field>
          <Field label="Teacher ID">
            <input value={form.teacher_id} onChange={(e) => setForm((f) => ({ ...f, teacher_id: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" />
          </Field>
          <Field label="Password">
            <input value={form.password} onChange={(e) => setForm((f) => ({ ...f, password: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" />
          </Field>
          <div className="flex items-end">
            <Button onClick={() => mut.mutate()} disabled={!form.full_name || !form.teacher_id} className="h-11 rounded-xl">
              Add
            </Button>
          </div>
        </div>
        {err && <p className="mt-3 text-sm text-[#a85a4c]">{err}</p>}
      </Panel>

      <Panel className="overflow-hidden p-0">
        {(teachers as any[]).length === 0 ? (
          <div className="p-5">
            <EmptyState title="No teachers yet" description="Use the form above to add the first teacher account." />
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-surface-2/70 text-left text-xs uppercase tracking-[0.08em] text-muted-foreground">
                <tr>
                  <th className="px-5 py-4">Teacher ID</th>
                  <th className="px-5 py-4">Name</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {(teachers as any[]).map((t) => (
                  <tr key={t.id} className="hover:bg-surface-2/40">
                    <td className="px-5 py-4 font-mono text-muted-foreground">{t.teacher_id}</td>
                    <td className="px-5 py-4">{t.full_name}</td>
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
