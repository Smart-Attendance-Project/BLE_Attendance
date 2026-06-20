import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Download } from "lucide-react";
import { getMyAssignments, exportAttendance } from "../../../api/endpoints";
import { Button } from "../../ui/button";
import { PageHeader, Panel, Field } from "../../components/shared/Primitives";

function getMondayOfWeek() {
  const d = new Date();
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  return new Date(new Date().setDate(diff)).toISOString().split("T")[0];
}

function getMonthStart() {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth(), 1).toISOString().split("T")[0];
}

const today = new Date().toISOString().split("T")[0];
const PRESETS = [
  { label: "This Week", from: getMondayOfWeek(), to: today },
  { label: "This Month", from: getMonthStart(), to: today },
];

export function Export() {
  const { data: assignments = [] } = useQuery({ queryKey: ["my-assignments"], queryFn: getMyAssignments });
  const [assignmentId, setAssignmentId] = useState("");
  const [fromDate, setFromDate] = useState(today);
  const [toDate, setToDate] = useState(today);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState("");

  const selected = (assignments as any[]).find((a) => String(a.id) === assignmentId);

  async function doExport() {
    if (!assignmentId) {
      setErr("Select a class first");
      return;
    }
    setErr("");
    setLoading(true);
    try {
      const res = await exportAttendance(Number(assignmentId), fromDate, toDate);
      const url = URL.createObjectURL(res.data);
      const a = document.createElement("a");
      a.href = url;
      a.download = `attendance_${fromDate}_to_${toDate}.xlsx`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      setErr("Export failed. No sessions may exist for this range.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="max-w-2xl">
      <PageHeader title="Export Attendance" subtitle="Download an Excel sheet for a class and date range." />

      <Panel>
        <div className="grid gap-6">
          <Field label="Class / Subject">
            <select
              value={assignmentId}
              onChange={(e) => setAssignmentId(e.target.value)}
              className="h-11 w-full rounded-lg border border-slate-200 bg-slate-50/50 px-4 text-sm text-muted-foreground outline-none transition focus:border-primary focus:ring-1 focus:ring-primary"
            >
              <option value="">Select a class</option>
              {(assignments as any[]).map((a) => (
                <option key={a.id} value={a.id}>
                  {a.subject_name} / {a.division_label}{a.batch_label ? ` / ${a.batch_label}` : ""}
                </option>
              ))}
            </select>
            {selected && <p className="mt-1 text-xs text-muted-foreground">{selected.subject_code} · {selected.batch_label ? "Lab" : "Lecture"}</p>}
          </Field>

          <div>
            <label className="mb-2 block text-sm font-semibold text-foreground">Quick range</label>
            <div className="flex flex-wrap gap-3">
              {PRESETS.map((p) => (
                <button
                  key={p.label}
                  onClick={() => { setFromDate(p.from); setToDate(p.to); }}
                  className="rounded-lg border border-slate-200 bg-slate-50 px-4 py-2 text-sm font-medium text-foreground transition hover:bg-slate-100"
                  type="button"
                >
                  {p.label}
                </button>
              ))}
            </div>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div className="bg-slate-50/50 p-4 rounded-lg border border-slate-100">
              <Field label="From">
                <input
                  type="date"
                  value={fromDate}
                  onChange={(e) => setFromDate(e.target.value)}
                  className="h-11 w-full rounded-lg border border-slate-200 bg-white px-4 text-sm text-foreground outline-none transition focus:border-primary focus:ring-1 focus:ring-primary"
                />
              </Field>
            </div>
            <div className="bg-slate-50/50 p-4 rounded-lg border border-slate-100">
              <Field label="To">
                <input
                  type="date"
                  value={toDate}
                  onChange={(e) => setToDate(e.target.value)}
                  className="h-11 w-full rounded-lg border border-slate-200 bg-white px-4 text-sm text-foreground outline-none transition focus:border-primary focus:ring-1 focus:ring-primary"
                />
              </Field>
            </div>
          </div>

          {err && <p className="rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">{err}</p>}

          <Button onClick={doExport} disabled={loading} className="h-12 w-full rounded-lg">
            <Download className="size-5" /> {loading ? "Exporting…" : "Download Excel"}
          </Button>
        </div>
      </Panel>
    </div>
  );
}
