import { useState } from "react";
import {
  LayoutDashboard,
  ListChecks,
  Download,
  Users,
  KeyRound,
  GraduationCap,
  UserCog,
  BookOpen,
  CalendarRange,
  LogOut,
  Menu,
  X,
} from "lucide-react";
import { cn } from "../ui/utils";
import type { NavKey, Role } from "../../lib/types";

interface NavItem {
  key: NavKey;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
}

const teacherNav: NavItem[] = [
  { key: "dashboard", label: "Dashboard", icon: LayoutDashboard },
  { key: "sessions", label: "Sessions", icon: ListChecks },
  { key: "export", label: "Export", icon: Download },
  { key: "students", label: "Students", icon: Users },
];

const adminNav: NavItem[] = [
  { key: "dashboard", label: "Dashboard", icon: LayoutDashboard },
  { key: "teachers", label: "Teachers", icon: GraduationCap },
  { key: "admins", label: "Admins", icon: UserCog },
  { key: "subjects", label: "Subjects", icon: BookOpen },
  { key: "schedule", label: "Schedule", icon: CalendarRange },
];

function Brand() {
  return (
    <div className="flex items-center">
      <span className="text-xl font-bold tracking-tight text-foreground">Attendance</span>
    </div>
  );
}

function initials(name: string) {
  return name
    .replace(/(Dr\.|Prof\.)\s*/g, "")
    .split(" ")
    .map((n) => n[0])
    .slice(0, 2)
    .join("");
}

export function Shell({
  role,
  current,
  onNavigate,
  onLogout,
  userName,
  children,
  isSuperAdmin,
}: {
  role: Role;
  current: NavKey;
  onNavigate: (key: NavKey) => void;
  onLogout: () => void;
  userName: string;
  isSuperAdmin?: boolean;
  children: React.ReactNode;
}) {
  const [mobileOpen, setMobileOpen] = useState(false);
  const nav = role === "teacher" ? teacherNav : adminNav;
  const allItems: NavItem[] = [...nav, { key: "password", label: "Password", icon: KeyRound }];

  return (
    <div className="min-h-screen bg-background">
      <header className="sticky top-0 z-30 border-b border-border bg-white/80 backdrop-blur-md">
        <div className="mx-auto flex h-16 max-w-7xl items-center gap-8 px-4 sm:px-6 lg:px-8">
          <Brand />

          <nav className="hidden flex-1 items-center gap-6 md:flex">
            {nav.map((item) => {
              const active = current === item.key;
              return (
                <button
                  key={item.key}
                  onClick={() => onNavigate(item.key)}
                  className={cn(
                    "relative pb-5 mt-5 text-sm font-medium transition-colors",
                    active
                      ? "text-foreground border-b-2 border-primary"
                      : "text-muted-foreground hover:text-primary"
                  )}
                >
                  {item.label}
                </button>
              );
            })}
          </nav>

          <div className="ml-auto flex items-center gap-4">
            <span
              className={cn(
                "hidden items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold sm:inline-flex",
                role === "admin"
                  ? "bg-sky-500/10 text-sky-500 border border-sky-500/20"
                  : "bg-sky-500/10 text-sky-500 border border-sky-500/20"
              )}
            >
              {role === "admin" ? (isSuperAdmin ? "Super Admin" : "Administrator") : "Teacher"}
            </span>

            <div className="group relative hidden md:block">
              <button className="flex items-center gap-2 rounded-md py-1 pl-1 pr-2.5 transition-colors hover:bg-surface-2">
                <span className="grid size-8 place-items-center rounded-full bg-sky-500 text-xs font-bold text-white">
                  {initials(userName)}
                </span>
                <span className="max-w-[120px] truncate text-sm font-medium text-sky-500">
                  {userName}
                </span>
              </button>
              <div className="invisible absolute right-0 top-full w-48 translate-y-1 rounded-lg border border-border bg-card p-1.5 opacity-0 shadow-[0_12px_32px_-12px_rgba(0,0,0,0.15)] transition-all group-hover:visible group-hover:translate-y-2 group-hover:opacity-100">
                <button
                  onClick={() => onNavigate("password")}
                  className="flex w-full items-center gap-2.5 rounded-md px-3 py-2 text-left text-sm text-muted-foreground hover:bg-surface-2 hover:text-foreground"
                >
                  <KeyRound className="size-4" /> Change password
                </button>
                <button
                  onClick={onLogout}
                  className="flex w-full items-center gap-2.5 rounded-md px-3 py-2 text-left text-sm text-muted-foreground hover:bg-error/10 hover:text-red-600"
                >
                  <LogOut className="size-4" /> Sign out
                </button>
              </div>
            </div>

            <button
              onClick={() => setMobileOpen((v) => !v)}
              className="grid size-9 place-items-center rounded-md border border-border text-muted-foreground md:hidden"
            >
              {mobileOpen ? <X className="size-5" /> : <Menu className="size-5" />}
            </button>
          </div>
        </div>

        {mobileOpen && (
          <div className="border-t border-border bg-card px-5 py-3 md:hidden">
            <div className="grid gap-1">
              {allItems.map((item) => {
                const Icon = item.icon;
                const active = current === item.key;
                return (
                  <button
                    key={item.key}
                    onClick={() => {
                      onNavigate(item.key);
                      setMobileOpen(false);
                    }}
                    className={cn(
                      "flex items-center gap-3 rounded-md px-3 py-2.5 text-left text-sm",
                      active ? "bg-primary/10 text-primary font-semibold" : "text-muted-foreground hover:bg-surface-2"
                    )}
                  >
                    <Icon className="size-[18px]" /> {item.label}
                  </button>
                );
              })}
              <button
                onClick={onLogout}
                className="mt-1 flex items-center gap-3 rounded-lg border-t border-border px-3 py-2.5 pt-3 text-left text-sm text-muted-foreground"
              >
                <LogOut className="size-[18px]" /> Sign out
              </button>
            </div>
          </div>
        )}
      </header>

      <main>
        <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 sm:py-10 lg:px-8">{children}</div>
      </main>
    </div>
  );
}
