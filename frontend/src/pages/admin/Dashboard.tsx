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
    { label: 'Teachers', value: teachers.length, icon: Users, link: '/admin/teachers' },
    { label: 'Branches', value: branches.length, icon: GitBranch, link: '/admin/schedule' },
    { label: 'Divisions', value: divisions.length, icon: Layers, link: '/admin/schedule' },
    { label: 'Active Semester', value: activeSem?.name || 'None', icon: Calendar, link: '/admin/schedule' },
  ]

  return (
    <div className="p-8 max-w-5xl mx-auto">
      <h1 className="text-3xl font-black text-zinc-900 mb-8">Admin Dashboard</h1>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-5 mb-10">
        {cards.map(c => (
          <Link key={c.label} to={c.link}
            className="bg-zinc-50 border-2 border-black rounded-xl p-5 shadow-[4px_4px_0_0_#000] hover:shadow-[2px_2px_0_0_#000] hover:translate-x-0.5 hover:translate-y-0.5 transition-all group">
            <div className="w-12 h-12 rounded-xl bg-indigo-100 border-2 border-black flex items-center justify-center mb-4">
              <c.icon size={22} className="text-indigo-700" />
            </div>
            <div className="text-3xl font-black text-zinc-900">{c.value}</div>
            <div className="text-base text-zinc-500 mt-1 font-medium">{c.label}</div>
          </Link>
        ))}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
        {[
          { to: '/admin/teachers', label: 'Manage Teachers', desc: 'Add and view teacher accounts' },
          { to: '/admin/schedule', label: 'Manage Schedule', desc: 'Semesters, branches, timetable' },
          { to: '/admin/subjects', label: 'Manage Subjects', desc: 'Subject codes and types' },
        ].map(item => (
          <Link key={item.to} to={item.to}
            className="bg-zinc-50 border-2 border-black rounded-xl p-5 shadow-[4px_4px_0_0_#000] hover:shadow-[2px_2px_0_0_#000] hover:translate-x-0.5 hover:translate-y-0.5 transition-all flex items-center justify-between group">
            <div>
              <div className="font-black text-zinc-900 text-lg">{item.label}</div>
              <div className="text-base text-zinc-500 mt-1">{item.desc}</div>
            </div>
            <ArrowRight size={20} className="text-zinc-300 group-hover:text-black transition-colors" />
          </Link>
        ))}
      </div>
    </div>
  )
}
