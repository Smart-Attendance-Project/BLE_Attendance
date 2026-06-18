import { useState } from "react";
import { AlertCircle, Loader2 } from "lucide-react";
import { useAuth } from "../../components/AuthContext";
import { Button } from "../ui/button";
import { Field, Panel } from "../components/shared/Primitives";
import { cn } from "../components/ui/utils";
import type { Role } from "../lib/types";

export function Login() {
  const { login } = useAuth();
  const [role, setRole] = useState<Role>("teacher");
  const [id, setId] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    if (!id.trim() || !password) {
      setError("Please enter both your ID and password.");
      return;
    }
    setLoading(true);
    try {
      await login(id.trim(), password);
    } catch {
      setError("The ID or password you entered is incorrect.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-[#f0f4f8] px-5 py-8">
      <div className="mx-auto flex min-h-[calc(100vh-4rem)] max-w-6xl flex-col justify-center">
        <div className="flex items-center justify-center">
          <div className="w-full max-w-[440px]">
            <Panel className="animate-rise-in border-slate-200 bg-white p-0 shadow-[0_4px_6px_-1px_rgba(0,0,0,0.1),0_2px_4px_-1px_rgba(0,0,0,0.06)]">
              <div className="px-8 pt-8 pb-0 md:px-12 md:pt-12">
                <h2 className="text-2xl font-bold text-foreground">Sign in</h2>
                <p className="mt-1 text-sm text-muted-foreground">Use your campus ID and password.</p>
              </div>

              <form onSubmit={submit} className="space-y-5 px-8 py-6 md:px-12 md:pb-12">
                <div className="inline-flex w-full rounded-lg bg-slate-100 p-1">
                  {(["teacher", "admin"] as Role[]).map((r) => (
                    <button
                      key={r}
                      type="button"
                      onClick={() => setRole(r)}
                      className={cn(
                        "flex-1 rounded-lg px-3 py-1.5 text-xs font-semibold capitalize transition-all",
                        role === r ? "bg-white text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground"
                      )}
                    >
                      {r}
                    </button>
                  ))}
                </div>

                <Field label={role === "admin" ? "Admin ID" : "Teacher ID"}>
                  <input
                    value={id}
                    onChange={(e) => setId(e.target.value)}
                    placeholder={role === "admin" ? "ADM-0001" : "FAC-1042"}
                    autoComplete="username"
                    className="h-11 w-full rounded-lg border border-slate-300 bg-white px-4 text-sm text-foreground outline-none transition placeholder:text-slate-400 focus:border-primary focus:ring-1 focus:ring-primary"
                  />
                </Field>

                <Field label="Password">
                  <input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="••••••••"
                    autoComplete="current-password"
                    className="h-11 w-full rounded-lg border border-slate-300 bg-white px-4 text-sm text-foreground outline-none transition placeholder:text-slate-400 focus:border-primary focus:ring-1 focus:ring-primary"
                  />
                </Field>

                {error && (
                  <div className="flex items-start gap-2 rounded-lg bg-red-50 px-3 py-2.5 text-sm text-red-700 ring-1 ring-inset ring-red-200">
                    <AlertCircle className="mt-0.5 size-4 shrink-0" />
                    {error}
                  </div>
                )}

                <Button type="submit" disabled={loading} className="h-11 w-full rounded-lg shadow-md">
                  {loading ? (
                    <>
                      <Loader2 className="size-4 animate-spin" /> Signing in…
                    </>
                  ) : (
                    "Sign in"
                  )}
                </Button>

                <div className="text-center">
                  <a href="#" className="text-xs text-muted-foreground hover:text-primary transition-colors">
                    Forgot password?
                  </a>
                </div>
              </form>
            </Panel>
          </div>
        </div>
      </div>
    </div>
  );
}
