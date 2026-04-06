import { Link, useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from './AuthContext'
import { LogOut, LayoutDashboard, Download, Users, BookOpen, Calendar, ShieldCheck, GraduationCap } from 'lucide-react'

export function Nav() {
  const { user, logout } = useAuth()
  const nav = useNavigate()
  const loc = useLocation()
  const handleLogout = () => { logout(); nav('/login') }

  const link = (to: string, label: string, Icon: React.ElementType) => {
    // exact match for dashboard, prefix match for others
    const active = to === '/teacher' || to === '/admin'
      ? loc.pathname === to
      : loc.pathname.startsWith(to)
    return (
      <Link to={to} className={`flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${active ? 'bg-white/20 text-white' : 'text-white/60 hover:bg-white/10 hover:text-white'}`}>
        <Icon size={15} />{label}
      </Link>
    )
  }

  return (
    <nav className="bg-zinc-900 border-b-2 border-black text-white px-5 py-3 flex items-center gap-2 shadow-[0_4px_0_0_#000]">
      <div className="flex items-center gap-2 mr-5">
        <div className="bg-yellow-400 text-black p-1 rounded border-2 border-black">
          <GraduationCap size={18} />
        </div>
        <span className="font-black text-base tracking-tight">BLE Attendance</span>
      </div>

      {user?.role === 'teacher' && <>
        {link('/teacher', 'Dashboard', LayoutDashboard)}
        {link('/teacher/sessions', 'Attendance', BookOpen)}
        {link('/teacher/export', 'Export', Download)}
        {link('/teacher/students', 'Students', Users)}
      </>}

      {user?.role === 'admin' && <>
        {link('/admin', 'Dashboard', LayoutDashboard)}
        {link('/admin/teachers', 'Teachers', Users)}
        {link('/admin/schedule', 'Schedule', Calendar)}
        {link('/admin/subjects', 'Subjects', BookOpen)}
        {user.is_super_admin && link('/admin/admins', 'Admins', ShieldCheck)}
      </>}

      {user && (
        <div className="ml-auto flex items-center gap-3">
          <span className="text-white/50 text-sm hidden sm:block">{user.full_name}</span>
          <button onClick={handleLogout} className="flex items-center gap-1.5 text-sm bg-white/10 hover:bg-white/20 px-3 py-1.5 rounded-lg transition-colors">
            <LogOut size={14} /> Logout
          </button>
        </div>
      )}
    </nav>
  )
}
