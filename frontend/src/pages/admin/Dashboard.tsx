import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { adminListTeachers, listSemesters, listBranches, listDivisions } from '../../api/endpoints'

export default function AdminDashboard() {
  const { data: teachers = [] } = useQuery({ queryKey: ['teachers'], queryFn: adminListTeachers })
  const { data: semesters = [] } = useQuery({ queryKey: ['semesters'], queryFn: listSemesters })
  const { data: branches = [] } = useQuery({ queryKey: ['branches'], queryFn: listBranches })
  const { data: divisions = [] } = useQuery({ queryKey: ['divisions'], queryFn: () => listDivisions() })

  const activeSem = semesters.find((s: any) => s.is_active)

  return (
    <div style={{ padding: 24 }}>
      <h2>Admin Dashboard</h2>
      <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap', marginBottom: 24 }}>
        {[
          { label: 'Teachers', value: teachers.length, link: '/admin/teachers' },
          { label: 'Branches', value: branches.length, link: '/admin/schedule' },
          { label: 'Divisions', value: divisions.length, link: '/admin/schedule' },
          { label: 'Active Semester', value: activeSem?.name || 'None', link: '/admin/schedule' },
        ].map(card => (
          <Link key={card.label} to={card.link} style={{ textDecoration: 'none' }}>
            <div style={{ border: '1px solid #ddd', borderRadius: 8, padding: '16px 24px', minWidth: 160, background: '#fafafa' }}>
              <div style={{ fontSize: 28, fontWeight: 700 }}>{card.value}</div>
              <div style={{ color: '#666', fontSize: 14 }}>{card.label}</div>
            </div>
          </Link>
        ))}
      </div>
      <div style={{ display: 'flex', gap: 12 }}>
        <Link to="/admin/teachers"><button>Manage Teachers</button></Link>
        <Link to="/admin/schedule"><button>Manage Schedule</button></Link>
        <Link to="/admin/subjects"><button>Manage Subjects</button></Link>
      </div>
    </div>
  )
}
