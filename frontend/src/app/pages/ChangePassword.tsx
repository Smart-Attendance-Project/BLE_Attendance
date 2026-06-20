import { useState } from "react";
import { changePassword } from "../../api/endpoints";
import { Button } from "../ui/button";
import { PageHeader, Panel, Field } from "../components/shared/Primitives";

export function ChangePassword() {
  const [oldPw, setOldPw] = useState("");
  const [newPw, setNewPw] = useState("");
  const [confirm, setConfirm] = useState("");
  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (newPw !== confirm) {
      setMsg({ ok: false, text: "New passwords do not match" });
      return;
    }
    setLoading(true);
    setMsg(null);
    try {
      await changePassword(oldPw, newPw);
      setMsg({ ok: true, text: "Password changed successfully" });
      setOldPw("");
      setNewPw("");
      setConfirm("");
    } catch (e: any) {
      setMsg({ ok: false, text: e?.response?.data?.detail ?? "Failed to change password" });
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="max-w-xl">
      <PageHeader title="Change Password" subtitle="Update your sign-in credentials." />
      <Panel>
        <form onSubmit={submit} className="grid gap-4">
          <Field label="Current password">
            <input value={oldPw} onChange={(e) => setOldPw(e.target.value)} type="password" required className="h-11 w-full rounded-lg border border-slate-200 bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-1 focus:ring-primary" />
          </Field>
          <Field label="New password">
            <input value={newPw} onChange={(e) => setNewPw(e.target.value)} type="password" required minLength={6} className="h-11 w-full rounded-lg border border-slate-200 bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-1 focus:ring-primary" />
          </Field>
          <Field label="Confirm new password">
            <input value={confirm} onChange={(e) => setConfirm(e.target.value)} type="password" required minLength={6} className="h-11 w-full rounded-lg border border-slate-200 bg-white px-4 text-sm outline-none transition focus:border-primary focus:ring-1 focus:ring-primary" />
          </Field>
          {msg && (
            <p className={`text-sm font-medium ${msg.ok ? "text-emerald-600" : "text-red-600"}`}>{msg.text}</p>
          )}
          <Button type="submit" disabled={loading} className="h-11 rounded-lg">
            {loading ? "Saving…" : "Change Password"}
          </Button>
        </form>
      </Panel>
    </div>
  );
}
