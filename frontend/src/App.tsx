import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './components/AuthContext'
import { Nav } from './components/Nav'
import { RequireAuth } from './components/RequireAuth'
import Login from './pages/auth/Login'
import TeacherDashboard from './pages/teacher/Dashboard'
import SessionList from './pages/teacher/SessionList'
import Export from './pages/teacher/Export'
import Students from './pages/teacher/Students'
import AdminDashboard from './pages/admin/Dashboard'
import Teachers from './pages/admin/Teachers'
import Admins from './pages/admin/Admins'
import Subjects from './pages/admin/Subjects'
import Schedule from './pages/admin/Schedule'

function RootRedirect() {
  const { user } = useAuth()
  if (!user) return <Navigate to="/login" replace />
  if (user.role === 'admin') return <Navigate to="/admin" replace />
  if (user.role === 'teacher') return <Navigate to="/teacher" replace />
  return <Navigate to="/login" replace />
}

export default function App() {
  const { user } = useAuth()
  return (
    <>
      {user && <Nav />}
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/" element={<RootRedirect />} />

        <Route path="/teacher" element={<RequireAuth role="teacher"><TeacherDashboard /></RequireAuth>} />
        <Route path="/teacher/sessions" element={<RequireAuth role="teacher"><SessionList /></RequireAuth>} />
        <Route path="/teacher/export" element={<RequireAuth role="teacher"><Export /></RequireAuth>} />
        <Route path="/teacher/students" element={<RequireAuth role="teacher"><Students /></RequireAuth>} />

        <Route path="/admin" element={<RequireAuth role="admin"><AdminDashboard /></RequireAuth>} />
        <Route path="/admin/teachers" element={<RequireAuth role="admin"><Teachers /></RequireAuth>} />
        <Route path="/admin/admins" element={<RequireAuth role="admin"><Admins /></RequireAuth>} />
        <Route path="/admin/subjects" element={<RequireAuth role="admin"><Subjects /></RequireAuth>} />
        <Route path="/admin/schedule" element={<RequireAuth role="admin"><Schedule /></RequireAuth>} />
      </Routes>
    </>
  )
}
