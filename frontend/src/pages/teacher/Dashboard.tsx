import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { getTodaySchedule } from '../../api/endpoints'
import { Clock, MapPin, Users, ArrowRight } from 'lucide-react'

const DAYS = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']

export default function TeacherDashboard() {
  const { data: slots = [], isLoading } = useQuery({ queryKey: ['today-schedule'], queryFn: getTodaySchedule })
  const today = new Date()
  const dayIdx = today.getDay() === 0 ? 6 : today.getDay() - 1
  const dateStr = today.toLocaleDateString('en-IN', { year: 'numeric', month: 'long', day: 'numeric' })

  return (
    <div className="p-8 max-w-5xl mx-auto">
      <div className="mb-8">
        <h1 className="text-3xl font-black text-zinc-900">Today's Schedule</h1>
        <p className="text-zinc-500 text-base mt-1">{DAYS[dayIdx]}, {dateStr}</p>
      </div>

      {isLoading && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
          {[1,2,3].map(i => <div key={i} className="h-40 bg-zinc-200 rounded-xl border-2 border-zinc-300 animate-pulse" />)}
        </div>
      )}

      {!isLoading && slots.length === 0 && (
        <div className="border-2 border-dashed border-zinc-300 rounded-xl py-20 text-center text-zinc-400">
          <Clock size={44} className="mx-auto mb-4 opacity-40" />
          <p className="font-semibold text-lg">No classes scheduled today</p>
        </div>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
        {slots.map((slot: any) => (
          <Link key={slot.id} to={`/teacher/sessions?assignment_id=${slot.assignment_id}`}
            className="group bg-zinc-50 border-2 border-black rounded-xl p-5 shadow-[4px_4px_0_0_#000] hover:shadow-[2px_2px_0_0_#000] hover:translate-x-0.5 hover:translate-y-0.5 transition-all">
            <div className="flex items-start justify-between mb-4">
              <span className="bg-indigo-100 border border-black text-indigo-800 text-sm font-bold px-3 py-1 rounded-lg">
                {slot.time_start} – {slot.time_end}
              </span>
              <ArrowRight size={18} className="text-zinc-300 group-hover:text-black transition-colors mt-0.5" />
            </div>
            <div className="font-black text-zinc-900 text-lg leading-tight">{slot.subject_name}</div>
            <div className="font-mono text-sm text-zinc-400 mt-1">{slot.subject_code}</div>
            <div className="flex flex-wrap gap-2 mt-4">
              <span className="flex items-center gap-1.5 text-sm text-zinc-600 bg-zinc-100 px-2.5 py-1 rounded-lg border border-zinc-200">
                <Users size={13} />{slot.division_label}{slot.batch_label ? ` / ${slot.batch_label}` : ''}
              </span>
              {slot.room && (
                <span className="flex items-center gap-1.5 text-sm text-zinc-600 bg-zinc-100 px-2.5 py-1 rounded-lg border border-zinc-200">
                  <MapPin size={13} />{slot.room}
                </span>
              )}
            </div>
          </Link>
        ))}
      </div>
    </div>
  )
}
