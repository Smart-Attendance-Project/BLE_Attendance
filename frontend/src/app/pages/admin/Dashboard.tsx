import { useQuery } from "@tanstack/react-query";
import { ChevronRight, CalendarCheck, BookOpen, GraduationCap, Layers, Network, UserCog } from "lucide-react";
import { adminListTeachers, listSemesters, listBranches, listDivisions } from "../../../api/endpoints";
import { PageHeader, StatCard } from "../../components/shared/Primitives";
import { StatusChip } from "../../components/shared/StatusChip";
import type { NavKey } from "../../lib/types";

const shortcuts: { key: NavKey; title: string; desc: string; icon: React.ComponentType<{ className?: string }>; tone: string }[] = [
  { key: "teachers", title: "Manage teachers", desc: "Add faculty and assign subjects", icon: GraduationCap, tone: "bg-primary/10 text-[#404a43]" },
  { key: "admins", title: "Admin accounts", desc: "Control access and permissions", icon: UserCog, tone: "bg-blush/30 text-[#9c6650]" },
  { key: "subjects", title: "Subjects", desc: "Lectures and lab courses", icon: BookOpen, tone: "bg-mint/30 text-[#3d6b4d]" },
  { key: "schedule", title: "Schedule", desc: "Semesters, divisions and timetable", icon: CalendarCheck, tone: "bg-butter/40 text-[#8a6a1f]" },
];

export function AdminDashboard({ onNavigate }: { onNavigate: (k: NavKey) => void }) {
  const { data: teachers = [] } = useQuery({ queryKey: ["teachers"], queryFn: adminListTeachers });
  const { data: semesters = [] } = useQuery({ queryKey: ["semesters"], queryFn: listSemesters });
  const { data: branches = [] } = useQuery({ queryKey: ["branches"], queryFn: listBranches });
  const { data: divisions = [] } = useQuery({ queryKey: ["divisions"], queryFn: listDivisions });
  const activeSem = (semesters as any[]).find((s) => s.is_active);

  return (
    <>
      <PageHeader
        title="Admin Overview"
        subtitle="Campus operations at a glance."
        actions={<StatusChip tone="active" dot>{activeSem ? activeSem.name : "No active semester"}</StatusChip>}
      />

      <div className="mb-7 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Teachers" value={(teachers as any[]).length} hint="faculty accounts" tone="primary" icon={<GraduationCap className="size-5" />} />
        <StatCard label="Branches" value={(branches as any[]).length} hint="institution branches" tone="mint" icon={<Network className="size-5" />} />
        <StatCard label="Divisions" value={(divisions as any[]).length} hint="class groupings" tone="blush" icon={<Layers className="size-5" />} />
        <StatCard label="Semester" value={activeSem ? "Active" : "None"} hint={activeSem?.name ?? "Activate one in Schedule"} tone="butter" icon={<CalendarCheck className="size-5" />} />
      </div>

      <div>
        <h2 className="mb-3 text-lg text-foreground">Admin tools</h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {shortcuts.map((s) => {
            const Icon = s.icon;
            return (
              <button
                key={s.key}
                onClick={() => onNavigate(s.key)}
                className="group flex items-center gap-4 rounded-lg border border-border bg-card p-5 text-left transition-shadow hover:shadow-[0_10px_28px_-18px_rgba(36,48,65,0.18)]"
              >
                <span className={"grid size-11 place-items-center rounded-lg " + s.tone}>
                  <Icon className="size-5" />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-foreground">{s.title}</p>
                  <p className="text-sm text-muted-foreground">{s.desc}</p>
                </div>
                <ChevronRight className="size-4 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
              </button>
            );
          })}
        </div>
      </div>
    </>
  );
}
