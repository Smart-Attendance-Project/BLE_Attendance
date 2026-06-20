import { cn } from "../ui/utils";

export function PageHeader({
  title,
  subtitle,
  actions,
  back,
}: {
  title: string;
  subtitle?: string;
  actions?: React.ReactNode;
  back?: React.ReactNode;
}) {
  return (
    <div className="mb-8 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
      <div className="space-y-1">
        {back}
        <h1 className="flex items-center gap-3 text-3xl font-bold leading-tight tracking-tight text-foreground lg:text-4xl">
          <span className="inline-block h-8 w-1.5 rounded-full bg-primary opacity-80" />
          {title}
        </h1>
        {subtitle && <p className="pl-[18px] text-sm text-muted-foreground">{subtitle}</p>}
      </div>
      {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
    </div>
  );
}

export function Panel({
  title,
  description,
  children,
  className,
  actions,
}: {
  title?: string;
  description?: string;
  children: React.ReactNode;
  className?: string;
  actions?: React.ReactNode;
}) {
  return (
    <section className={cn("overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm", className)}>
      {(title || actions) && (
        <header className="flex items-center justify-between gap-3 border-b border-slate-200 px-6 py-4">
          <div className="space-y-0.5">
            {title && <h3 className="text-base font-semibold text-foreground">{title}</h3>}
            {description && <p className="text-sm text-muted-foreground">{description}</p>}
          </div>
          {actions}
        </header>
      )}
      <div className="p-6">{children}</div>
    </section>
  );
}

export function StatCard({
  label,
  value,
  hint,
  icon,
  tone = "primary",
}: {
  label: string;
  value: React.ReactNode;
  hint?: string;
  icon?: React.ReactNode;
  tone?: "primary" | "mint" | "blush" | "butter";
}) {
  const accent: Record<string, string> = {
    primary: "text-primary",
    mint: "text-primary",
    blush: "text-primary",
    butter: "text-primary",
  };

  return (
    <div className="rounded-lg border border-slate-200 bg-white p-6 shadow-sm transition-shadow hover:shadow-md">
      <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-muted-foreground mb-3">
        {icon && <span className={cn("[&_svg]:size-4", accent[tone])}>{icon}</span>}
        <p>{label}</p>
      </div>
      <p className="text-4xl font-semibold leading-none text-foreground">{value}</p>
      {hint && <p className="mt-2 text-xs text-muted-foreground">{hint}</p>}
    </div>
  );
}

export function EmptyState({
  icon,
  title,
  description,
  action,
}: {
  icon?: React.ReactNode;
  title: string;
  description?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 rounded-lg border border-dashed border-slate-300 bg-slate-50/60 px-6 py-14 text-center">
      {icon && <span className="grid size-12 place-items-center rounded-lg bg-white text-muted-foreground shadow-sm">{icon}</span>}
      <div className="space-y-1">
        <p className="text-base font-medium text-foreground">{title}</p>
        {description && <p className="mx-auto max-w-sm text-sm text-muted-foreground">{description}</p>}
      </div>
      {action}
    </div>
  );
}

export function Field({
  label,
  hint,
  error,
  children,
}: {
  label: string;
  hint?: string;
  error?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <label className="text-xs font-bold uppercase tracking-wider text-muted-foreground">{label}</label>
      {children}
      {error ? <p className="text-xs text-error">{error}</p> : hint ? <p className="text-xs text-muted-foreground">{hint}</p> : null}
    </div>
  );
}
