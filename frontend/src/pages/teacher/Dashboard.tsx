import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { getTodaySchedule } from '../../api/endpoints'

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']

export default function TeacherDashboard() {
  const { data: slots = [], isLoading } = useQuery({ queryKey: ['today-schedule'], queryFn: getTodaySchedule })
  const today = new Date().toLocaleDateString('en-IN', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })

  return (
    <div style={{ padding: 24 }}>
      <h2>Today's Schedule</h2>
      <p style={{ color: '#666' }}>{today}</p>
      {isLoading && <p>Loading…</p>}
      {!isLoading && slots.length === 0 && <p>No classes scheduled today.</p>}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, maxWidth: 700 }}>
        {slots.map((slot: any) => (
          <div key={slot.id} style={{ border: '1px solid #ddd', borderRadius: 8, padding: 16, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <strong>{slot.subject_name}</strong> <span style={{ color: '#888', fontSize: 13 }}>({slot.subject_code})</span>
              <div style={{ fontSize: 13, color: '#555', marginTop: 4 }}>
                {slot.division_label}{slot.batch_label ? ` · Batch ${slot.batch_label}` : ''} · {slot.room || 'TBD'}
              </div>
              <div style={{ fontSize: 13, color: '#555' }}>{slot.time_start} – {slot.time_end}</div>
            </div>
            <Link to={`/teacher/sessions?assignment_id=${slot.assignment_id}`}>
              <button>View Attendance</button>
            </Link>
          </div>
        ))}
      </div>
    </div>
  )
}
