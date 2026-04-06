import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { getTodaySchedule } from '../../api/endpoints'
import { Clock, MapPin, Users, ChevronRight } from 'lucide-react'

const DAYS = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']

export default function TeacherDashboard() {
  const { data: slots = [], isLoading } = useQuery({ queryKey: ['today-schedule'], queryFn: getTodaySchedule })
  const today = new Date()
  const dayName = DAYS[today.getDay() === 0 ? 6 : today.getDay() - 1]
  const dateStr = today.toLocaleDateString('en-IN', { year: 'numeric', month: 'long', day: 'numeric' })

  return (
    <div className="p-6 max-w-3xl mx-auto">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Today's Schedule</h1>
        <p className="text-gray-500 text-sm mt-1">{dayName}, {dateStr}</p>
      </div>

      {isLoading && (
        <div className="flex gap-3 flex-col">
          {[1,2,3].map(i => <div key={i} className="h-24 bg-gray-100 rounded-xl animate-pulse" />)}
        </div>
      )}

      {!isLoading && slots.length === 0 && (
        <div className="text-center py-16 text-gray-400">
          <Clock size={40} className="mx-auto mb-3 opacity-40" />
          <p className="font-medium">No classes scheduled today</p>
        </div>
      )}

      <div className="flex flex-col gap-3">
        {slots.map((slot: any) => (
          <Link key={slot.id} to={`/teacher/sessions?assignment_id=${slot.assignment_id}`}
            className="group bg-white border border-gray-200 rounded-xl p-4 hover:border-indigo-300 hover:shadow-md transition-all flex items-center gap-4">
            <div className="bg-indigo-50 text-indigo-700 rounded-lg px-3 py-2 text-center min-w-[72px]">
              <div className="text-xs font-medium">{slot.time_start}</div>
              <div className="text-xs text-indigo-400">–</div>
              <div className="text-xs font-medium">{slot.time_end}</div>
            </div>
            <div className="flex-1 min-w-0">
              <div className="font-semibold text-gray-900 truncate">{slot.subject_name}</div>
              <div className="text-xs text-gray-500 mt-0.5 font-mono">{slot.subject_code}</div>
              <div className="flex items-center gap-3 mt-1.5 text-xs text-gray-500">
                <span className="flex items-center gap-1"><Users size={11} />{slot.division_label}{slot.batch_label ? ` · Batch ${slot.batch_label}` : ''}</span>
                {slot.room && <span className="flex items-center gap-1"><MapPin size={11} />{slot.room}</span>}
              </div>
            </div>
            <ChevronRight size={18} className="text-gray-300 group-hover:text-indigo-400 transition-colors" />
          </Link>
        ))}
      </div>
    </div>
  )
}
