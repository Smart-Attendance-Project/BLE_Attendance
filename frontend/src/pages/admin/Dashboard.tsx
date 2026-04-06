import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { adminListTeachers, listSemesters, listBranches, listDivisions } from '../../api/endpoints'
import { Users, GitBranch, Layers, Calendar, ArrowRight } from 'lucide-react'

export default function AdminDashboard() {
  const { data: teachers = [] } = useQuery({ queryKey: ['teachers'], queryFn: adminListTeachers })
  const { data: semesters = [] } = useQuery({ queryKey: ['semesters'], queryFn: listSemesters })
  const { data: branches = [] } = useQuery({ queryKey: ['branches'], queryFn: listBranches })
  const { data: divisions = [] } = useQuery({ queryKey: ['divisions'], queryFn: () => listDivisions() })
  const activeSem = semesters.find((s: any) => s.is_active)

  const cards = [
    { label: 'Teachers', value: teachers.length, icon: Users, link: '/admin/teachers', color: 'bg-blue-50 text-blue-600' },
    { label: 'Branches', value: branches.length, icon: GitBranch, link: '/admin/schedule', color: 'bg-purple-50 text-purple-600' },
    { label: 'Divisions', value: divisions.length, icon: Layers, link: '/admin/schedule', color: 'bg-orange-50 text-orange-600' },
    { label: 'Active Semester', value: activeSem?.name || 'None', icon: Calendar, link: '/admin/schedule', color: 'bg-green-50 text-green-600' },
  ]

  return (
    <div className="p-6 max-w-5xl mx-auto">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Admin Dashboard</h1>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        {cards.map(c => (
          <Link key={c.label} to={c.link} className="bg-zinc-50 border border-gray-200 rounded-xl p-4 hover:shadow-md hover:border-gray-300 transition-all group">
            <div className={`w-10 h-10 rounded-lg flex items-center justify-center mb-3 ${c.color}`}>
              <c.icon size={20} />
            </div>
            <div className="text-2xl font-bold text-gray-900">{c.value}</div>
            <div className="text-sm text-gray-500 mt-0.5">{c.label}</div>
          </Link>
        ))}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {[
          { to: '/admin/teachers', label: 'Manage Teachers', desc: 'Add and view teacher accounts' },
          { to: '/admin/schedule', label: 'Manage Schedule', desc: 'Semesters, branches, timetable' },
          { to: '/admin/subjects', label: 'Manage Subjects', desc: 'Subject codes and types' },
        ].map(item => (
          <Link key={item.to} to={item.to}
            className="bg-zinc-50 border border-gray-200 rounded-xl p-4 hover:border-indigo-300 hover:shadow-md transition-all flex items-center justify-between group">
            <div>
              <div className="font-semibold text-gray-900">{item.label}</div>
              <div className="text-sm text-gray-500 mt-0.5">{item.desc}</div>
            </div>
            <ArrowRight size={18} className="text-gray-300 group-hover:text-indigo-400 transition-colors" />
          </Link>
        ))}
      </div>
    </div>
  )
}
