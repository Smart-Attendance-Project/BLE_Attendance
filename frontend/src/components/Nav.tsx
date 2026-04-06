import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from './AuthContext'

export function Nav() {
  const { user, logout } = useAuth()
  const nav = useNavigate()
  const handleLogout = () => { logout(); nav('/login') }

  return (
    <nav style={{ padding: '10px 20px', background: '#1a1a2e', color: '#fff', display: 'flex', gap: 20, alignItems: 'center' }}>
      <strong>BLE Attendance</strong>
      {user?.role === 'teacher' && <>
        <Link to="/teacher" style={{ color: '#ccc' }}>Dashboard</Link>
        <Link to="/teacher/export" style={{ color: '#ccc' }}>Export</Link>
        <Link to="/teacher/students" style={{ color: '#ccc' }}>Students</Link>
      </>}
      {user?.role === 'admin' && <>
        <Link to="/admin" style={{ color: '#ccc' }}>Dashboard</Link>
        <Link to="/admin/teachers" style={{ color: '#ccc' }}>Teachers</Link>
        <Link to="/admin/schedule" style={{ color: '#ccc' }}>Schedule</Link>
        <Link to="/admin/subjects" style={{ color: '#ccc' }}>Subjects</Link>
        {user.is_super_admin && <Link to="/admin/admins" style={{ color: '#ccc' }}>Admins</Link>}
      </>}
      {user && <button onClick={handleLogout} style={{ marginLeft: 'auto', cursor: 'pointer' }}>Logout ({user.full_name})</button>}
    </nav>
  )
}
