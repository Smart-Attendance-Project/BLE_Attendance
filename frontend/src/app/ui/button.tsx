import { cn } from "./utils";

export function Button({
  className,
  variant = "default",
  size = "default",
  ...props
}: React.ComponentProps<"button"> & {
  variant?: "default" | "outline" | "ghost" | "destructive";
  size?: "default" | "sm" | "lg";
}) {
  const variantClass =
    variant === "outline"
      ? "border border-slate-200 bg-white text-foreground hover:bg-slate-50"
      : variant === "ghost"
      ? "bg-transparent text-foreground hover:bg-slate-100"
      : variant === "destructive"
      ? "bg-red-500 text-white hover:bg-red-600"
      : "bg-primary text-white hover:bg-[#0f766e] shadow-sm";

  const sizeClass = size === "sm" ? "h-9 px-4 text-xs font-bold" : size === "lg" ? "h-11 px-6 text-base" : "h-10 px-5 text-sm font-semibold";

  return (
    <button
      {...props}
      className={cn(
        "inline-flex items-center justify-center gap-2 rounded-lg transition-all disabled:pointer-events-none disabled:opacity-50",
        variantClass,
        sizeClass,
        className
      )}
    />
  );
}
