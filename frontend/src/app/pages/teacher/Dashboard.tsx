import { useQuery } from "@tanstack/react-query";
import { CalendarDays, Clock, MapPin, Users, Play, Radio, CalendarX, CheckCircle2 } from "lucide-react";
import { getTodaySchedule, getMyAssignments } from "../../../api/endpoints";
import { Button } from "../../ui/button";
import { PageHeader, StatCard, EmptyState, Panel } from "../../components/shared/Primitives";
import { StatusChip } from "../../components/shared/StatusChip";
import type { TeacherScheduleSlot } from "../../lib/types";

function ClassRow({ cls, onOpen }: { cls: TeacherScheduleSlot; onOpen: () => void }) {
  return (
    <button onClick={onOpen} className="flex w-full items-center gap-12 px-8 py-6 text-left transition-colors hover:bg-slate-50">
      <div className="w-20 shrink-0 text-center" data-purpose="session-time">
        <p className="text-sm font-semibold text-foreground">{cls.time_start}</p>
        <p className="text-xs text-muted-foreground mt-1">{cls.time_end}</p>
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-3 mb-1">
          <p className="text-lg font-semibold text-foreground">{cls.subject_name}</p>
          <StatusChip tone={cls.batch_label ? "lab" : "lecture"}>{cls.batch_label ? "Lab" : "Lecture"}</StatusChip>
        </div>
        <div className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-muted-foreground font-medium">
          <span className="uppercase">{cls.subject_code}</span>
          <span className="text-slate-300">•</span>
          <span className="uppercase">
            {cls.division_label}{cls.batch_label ? ` · Batch ${cls.batch_label}` : ""}
          </span>
          <span className="text-slate-300">•</span>
          <span className="inline-flex items-center gap-1">
            <MapPin className="size-3 text-primary" /> <span className="uppercase">{cls.room ?? "—"}</span>
          </span>
        </div>
      </div>
    </button>
  );
}

export function TeacherDashboard({ onGoSessions }: { onGoSessions: () => void }) {
  const { data: slots = [], isLoading } = useQuery({ queryKey: ["today-schedule"], queryFn: getTodaySchedule, refetchInterval: 30_000 });
  const { data: assignments = [] } = useQuery({ queryKey: ["my-assignments"], queryFn: getMyAssignments, refetchInterval: 60_000 });
  const today = new Date();
  const dateStr = today.toLocaleDateString("en-IN", { weekday: "long", year: "numeric", month: "long", day: "numeric" });
  const activeSlot = slots.find((s: TeacherScheduleSlot) => s.time_start <= new Date().toTimeString().slice(0, 5) && s.time_end >= new Date().toTimeString().slice(0, 5));

  return (
    <>
      <PageHeader
        title="Today's Schedule"
        subtitle={`${dateStr} · ${slots.length} classes scheduled`}
        actions={
          <Button onClick={onGoSessions} className="rounded-lg">
            <Play className="size-4" /> Open sessions
          </Button>
        }
      />

      <div className="mb-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Classes today" value={slots.length} hint={`${assignments.length} assigned classes`} tone="primary" icon={<CalendarDays />} />
        <StatCard label="Active class" value={activeSlot ? activeSlot.subject_code : "None"} hint={activeSlot ? activeSlot.subject_name : "No class in progress"} tone="mint" icon={<Radio />} />
        <StatCard label="Assignments" value={assignments.length} hint="linked to your profile" tone="butter" icon={<Users />} />
        <StatCard label="Pending reviews" value="0" hint="attendance is up to date" tone="blush" icon={<CheckCircle2 />} />
      </div>

      <div className="mb-4 flex items-end justify-between">
        <h2 className="text-xl font-bold text-foreground">Today's classes</h2>
        <button onClick={onGoSessions} className="text-xs font-medium text-primary hover:text-[#0f766e] flex items-center gap-1 transition-colors">
          View all sessions <span className="text-sm">→</span>
        </button>
      </div>

      {isLoading ? (
        <Panel>
          <div className="grid gap-3">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="h-20 animate-pulse rounded-lg bg-slate-100" />
            ))}
          </div>
        </Panel>
      ) : slots.length > 0 ? (
        <Panel className="overflow-hidden p-0">
          <div className="divide-y divide-slate-200">
            {slots.map((cls: TeacherScheduleSlot) => (
              <ClassRow key={cls.id} cls={cls} onOpen={onGoSessions} />
            ))}
          </div>
        </Panel>
      ) : (
        <EmptyState
          icon={<CalendarX className="size-6" />}
          title="No classes scheduled today"
          description="Your assigned classes will appear here once the schedule is active."
        />
      )}
    </>
  );
}
