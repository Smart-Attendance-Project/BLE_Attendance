import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { adminListAdmins, adminCreateAdmin } from "../../../api/endpoints";
import { useAuth } from "../../../components/AuthContext";
import { Button } from "../../ui/button";
import { PageHeader, Panel, Field, EmptyState } from "../../components/shared/Primitives";
import { StatusChip } from "../../components/shared/StatusChip";

export function Admins() {
  const { user } = useAuth();
  const qc = useQueryClient();
  const { data: admins = [] } = useQuery({ queryKey: ["admins"], queryFn: adminListAdmins });
  const [form, setForm] = useState({ full_name: "", admin_id: "", password: "Pass@123", is_super_admin: false });
  const [err, setErr] = useState("");

  const mut = useMutation({
    mutationFn: () => adminCreateAdmin(form),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["admins"] });
      setForm({ full_name: "", admin_id: "", password: "Pass@123", is_super_admin: false });
      setErr("");
    },
    onError: (e: any) => setErr(e.response?.data?.detail || "Error"),
  });

  return (
    <div className="max-w-5xl">
      <PageHeader title="Admin Accounts" subtitle="Control access and super-admin privileges." />

      <Panel className="mb-8">
        <div className="grid gap-4 md:grid-cols-[1.1fr_0.8fr_0.8fr_auto]">
          <Field label="Full name">
            <input value={form.full_name} onChange={(e) => setForm((f) => ({ ...f, full_name: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" />
          </Field>
          <Field label="Admin ID">
            <input value={form.admin_id} onChange={(e) => setForm((f) => ({ ...f, admin_id: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" />
          </Field>
          <Field label="Password">
            <input value={form.password} onChange={(e) => setForm((f) => ({ ...f, password: e.target.value }))} className="h-11 w-full rounded-xl border border-border bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-4 focus:ring-primary/15" />
          </Field>
          <div className="flex items-end gap-3">
            {user?.is_super_admin ? (
              <label className="flex items-center gap-2 text-sm text-muted-foreground">
                <input type="checkbox" checked={form.is_super_admin} onChange={(e) => setForm((f) => ({ ...f, is_super_admin: e.target.checked }))} />
                Super admin
              </label>
            ) : (
              <StatusChip tone="neutral">Admin can create only standard admins</StatusChip>
            )}
            <Button onClick={() => mut.mutate()} disabled={!form.full_name || !form.admin_id} className="h-11 rounded-xl">
              Add
            </Button>
          </div>
        </div>
        {err && <p className="mt-3 text-sm text-[#a85a4c]">{err}</p>}
      </Panel>

      <Panel className="overflow-hidden p-0">
        {(admins as any[]).length === 0 ? (
          <div className="p-5">
            <EmptyState title="No admin accounts" description="Create the first admin account above." />
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-surface-2/70 text-left text-xs uppercase tracking-[0.08em] text-muted-foreground">
                <tr>
                  <th className="px-5 py-4">Admin ID</th>
                  <th className="px-5 py-4">Name</th>
                  <th className="px-5 py-4">Role</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {(admins as any[]).map((a) => (
                  <tr key={a.id} className="hover:bg-surface-2/40">
                    <td className="px-5 py-4 font-mono text-muted-foreground">{a.admin_id}</td>
                    <td className="px-5 py-4">{a.full_name}</td>
                    <td className="px-5 py-4">{a.is_super_admin ? <StatusChip tone="active">Super Admin</StatusChip> : <StatusChip tone="neutral">Admin</StatusChip>}</td>
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
