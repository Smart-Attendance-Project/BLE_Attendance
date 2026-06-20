import { useEffect, useState } from "react";
import { useAuth } from "./components/AuthContext";
import { Shell } from "./app/components/layout/Shell";
import type { NavKey } from "./app/lib/types";
import { Login } from "./app/pages/Login";
import { ChangePassword } from "./app/pages/ChangePassword";
import { TeacherDashboard } from "./app/pages/teacher/Dashboard";
import { Sessions } from "./app/pages/teacher/Sessions";
import { Export } from "./app/pages/teacher/Export";
import { Students } from "./app/pages/teacher/Students";
import { AdminDashboard } from "./app/pages/admin/Dashboard";
import { Teachers } from "./app/pages/admin/Teachers";
import { Admins } from "./app/pages/admin/Admins";
import { Subjects } from "./app/pages/admin/Subjects";
import { Schedule } from "./app/pages/admin/Schedule";

export default function App() {
  const { user, loading, logout } = useAuth();
  const [page, setPage] = useState<NavKey>("dashboard");

  useEffect(() => {
    if (user) setPage("dashboard");
  }, [user]);

  if (loading) {
    return <div className="min-h-screen bg-background" />;
  }

  if (!user) {
    return <Login />;
  }

  function render() {
    if (page === "password") return <ChangePassword />;
    if (user.role === "teacher") {
      switch (page) {
        case "sessions":
          return <Sessions />;
        case "export":
          return <Export />;
        case "students":
          return <Students />;
        default:
          return <TeacherDashboard onGoSessions={() => setPage("sessions")} />;
      }
    }
    switch (page) {
      case "teachers":
        return <Teachers />;
      case "admins":
        return <Admins />;
      case "subjects":
        return <Subjects />;
      case "schedule":
        return <Schedule />;
      default:
        return <AdminDashboard onNavigate={setPage} />;
    }
  }

  return (
    <Shell
      role={user.role}
      current={page}
      onNavigate={setPage}
      onLogout={logout}
      userName={user.full_name}
      isSuperAdmin={user.is_super_admin}
    >
      <div key={page} className="animate-page-in">
        {render()}
      </div>
    </Shell>
  );
}
