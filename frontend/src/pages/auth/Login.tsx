import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../../components/AuthContext'
import { GraduationCap } from 'lucide-react'

export default function Login() {
  const { login } = useAuth()
  const nav = useNavigate()
  const [id, setId] = useState('')
  const [pw, setPw] = useState('')
  const [err, setErr] = useState('')
  const [loading, setLoading] = useState(false)

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setErr('')
    setLoading(true)
    try {
      await login(id, pw)
      nav('/')
    } catch {
      setErr('Invalid credentials. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-indigo-950 via-indigo-900 to-indigo-800 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-sm p-8">
        <div className="flex flex-col items-center mb-8">
          <div className="bg-indigo-100 p-3 rounded-full mb-3">
            <GraduationCap size={32} className="text-indigo-600" />
          </div>
          <h1 className="text-2xl font-bold text-gray-900">BLE Attendance</h1>
          <p className="text-gray-500 text-sm mt-1">Sign in to your account</p>
        </div>

        <form onSubmit={submit} className="flex flex-col gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">ID</label>
            <input
              className="w-full border border-gray-300 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
              placeholder="T001 / ADMIN001 / 25CE001"
              value={id} onChange={e => setId(e.target.value)} required
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Password</label>
            <input
              type="password"
              className="w-full border border-gray-300 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
              placeholder="••••••••"
              value={pw} onChange={e => setPw(e.target.value)} required
            />
          </div>
          {err && <p className="text-red-600 text-sm bg-red-50 border border-red-200 rounded-lg px-3 py-2">{err}</p>}
          <button
            type="submit" disabled={loading}
            className="bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white font-semibold py-2.5 rounded-lg transition-colors mt-1"
          >
            {loading ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
