import { cn } from "../ui/utils";
import type { SessionStatus } from "../../lib/types";

type Tone =
  | "active"
  | "locked"
  | "ended"
  | "editable"
  | "present"
  | "absent"
  | "warning"
  | "success"
  | "neutral"
  | "info"
  | "lecture"
  | "lab";

const toneStyles: Record<Tone, string> = {
  active: "bg-emerald-50 text-emerald-700 ring-emerald-200",
  success: "bg-emerald-50 text-emerald-700 ring-emerald-200",
  present: "bg-emerald-50 text-emerald-700 ring-emerald-200",
  locked: "bg-slate-100 text-slate-600 ring-slate-200",
  ended: "bg-slate-100 text-slate-600 ring-slate-200",
  neutral: "bg-slate-100 text-slate-600 ring-slate-200",
  editable: "bg-amber-50 text-amber-700 ring-amber-200",
  warning: "bg-amber-50 text-amber-700 ring-amber-200",
  absent: "bg-red-50 text-red-700 ring-red-200",
  info: "bg-teal-50 text-teal-700 ring-teal-200",
  lecture: "bg-teal-50 text-teal-700 ring-teal-200",
  lab: "bg-teal-50 text-teal-700 ring-teal-200",
};

const labels: Partial<Record<Tone, string>> = {
  active: "Active",
  locked: "Locked",
  ended: "Ended",
  editable: "Editable",
};

export function StatusChip({
  tone,
  children,
  dot = false,
  className,
}: {
  tone: Tone | SessionStatus;
  children?: React.ReactNode;
  dot?: boolean;
  className?: string;
}) {
  return (
    <span className={cn("inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider ring-1 ring-inset", toneStyles[tone as Tone], className)}>
      {dot && <span className="size-1.5 rounded-full bg-current opacity-80" />}
      {children ?? labels[tone as Tone] ?? tone}
    </span>
  );
}
