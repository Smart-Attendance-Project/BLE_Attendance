import { Link, useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from './AuthContext'
import { LogOut, LayoutDashboard, Download, Users, BookOpen, Calendar, ShieldCheck, GraduationCap } from 'lucide-react'

export function Nav() {
  const { user, logout } = useAuth()
  const nav = useNavigate()
  const loc = useLocation()

  const handleLogout = () => { logout(); nav('/login') }

  const link = (to: string, label: string, Icon: React.ElementType) => {
    const active = loc.pathname === to || loc.pathname.startsWith(to + '/')
    return (
      <Link to={to} className={`flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${active ? 'bg-indigo-700 text-white' : 'text-indigo-200 hover:bg-indigo-700/60 hover:text-white'}`}>
        <Icon size={16} />{label}
      </Link>
    )
  }

  return (
    <nav className="bg-indigo-900 text-white px-4 py-3 flex items-center gap-2 shadow-lg">
      <div className="flex items-center gap-2 mr-4">
        <GraduationCap size={22} className="text-indigo-300" />
        <span className="font-bold text-base tracking-tight">BLE Attendance</span>
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
          <span className="text-indigo-300 text-sm">{user.full_name}</span>
          <button onClick={handleLogout} className="flex items-center gap-1.5 text-sm text-indigo-200 hover:text-white transition-colors">
            <LogOut size={15} /> Logout
          </button>
        </div>
      )}
    </nav>
  )
}
