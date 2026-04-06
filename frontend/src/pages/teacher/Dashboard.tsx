import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { getTodaySchedule } from '../../api/endpoints'
import { Clock, MapPin, Users, ArrowRight } from 'lucide-react'

const DAYS = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']

export default function TeacherDashboard() {
  const { data: slots = [], isLoading } = useQuery({ queryKey: ['today-schedule'], queryFn: getTodaySchedule })
  const today = new Date()
  const dayIdx = today.getDay() === 0 ? 6 : today.getDay() - 1
  const dayName = DAYS[dayIdx]
  const dateStr = today.toLocaleDateString('en-IN', { year: 'numeric', month: 'long', day: 'numeric' })

  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="mb-6">
        <h1 className="text-2xl font-black text-zinc-900">Today's Schedule</h1>
        <p className="text-zinc-500 text-sm mt-1">{dayName}, {dateStr}</p>
      </div>

      {isLoading && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1,2,3].map(i => <div key={i} className="h-32 bg-zinc-100 rounded-xl border-2 border-zinc-200 animate-pulse" />)}
        </div>
      )}

      {!isLoading && slots.length === 0 && (
        <div className="border-2 border-dashed border-zinc-300 rounded-xl py-16 text-center text-zinc-400">
          <Clock size={36} className="mx-auto mb-3 opacity-40" />
          <p className="font-semibold">No classes scheduled today</p>
        </div>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {slots.map((slot: any) => (
          <Link key={slot.id} to={`/teacher/sessions?assignment_id=${slot.assignment_id}`}
            className="group bg-white border-2 border-black rounded-xl p-4 shadow-[4px_4px_0_0_#000] hover:shadow-[2px_2px_0_0_#000] hover:translate-x-0.5 hover:translate-y-0.5 transition-all">
            <div className="flex items-start justify-between mb-3">
              <span className="bg-indigo-100 border border-black text-black text-xs font-bold px-2 py-0.5 rounded">
                {slot.time_start}–{slot.time_end}
              </span>
              <ArrowRight size={16} className="text-zinc-300 group-hover:text-black transition-colors mt-0.5" />
            </div>
            <div className="font-black text-zinc-900 leading-tight">{slot.subject_name}</div>
            <div className="font-mono text-xs text-zinc-400 mt-0.5">{slot.subject_code}</div>
            <div className="flex flex-wrap gap-2 mt-3">
              <span className="flex items-center gap-1 text-xs text-zinc-600 bg-zinc-100 px-2 py-0.5 rounded-full border border-zinc-200">
                <Users size={10} />{slot.division_label}{slot.batch_label ? ` · ${slot.batch_label}` : ''}
              </span>
              {slot.room && (
                <span className="flex items-center gap-1 text-xs text-zinc-600 bg-zinc-100 px-2 py-0.5 rounded-full border border-zinc-200">
                  <MapPin size={10} />{slot.room}
                </span>
              )}
            </div>
          </Link>
        ))}
      </div>
    </div>
  )
}
