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
    <div className="min-h-screen bg-yellow-400 flex items-center justify-center p-4">
      <div className="bg-white border-2 border-black rounded-2xl shadow-[8px_8px_0_0_#000] w-full max-w-sm p-8">
        <div className="flex flex-col items-center mb-8">
          <div className="bg-zinc-900 text-yellow-400 p-3 rounded-xl border-2 border-black shadow-[4px_4px_0_0_#000] mb-4">
            <GraduationCap size={28} />
          </div>
          <h1 className="text-2xl font-black text-zinc-900">BLE Attendance</h1>
          <p className="text-zinc-500 text-sm mt-1">Sign in to continue</p>
        </div>

        <form onSubmit={submit} className="flex flex-col gap-4">
          <div>
            <label className="block text-sm font-bold text-zinc-700 mb-1">ID</label>
            <input
              className="w-full border-2 border-black rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-yellow-400 shadow-[2px_2px_0_0_#000]"
              placeholder="T001 / ADMIN001"
              value={id} onChange={e => setId(e.target.value)} required
            />
          </div>
          <div>
            <label className="block text-sm font-bold text-zinc-700 mb-1">Password</label>
            <input
              type="password"
              className="w-full border-2 border-black rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-yellow-400 shadow-[2px_2px_0_0_#000]"
              placeholder="••••••••"
              value={pw} onChange={e => setPw(e.target.value)} required
            />
          </div>
          {err && <p className="text-red-700 text-sm bg-red-50 border-2 border-red-300 rounded-lg px-3 py-2 font-medium">{err}</p>}
          <button
            type="submit" disabled={loading}
            className="bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 text-white font-black py-3 rounded-xl border-2 border-black shadow-[4px_4px_0_0_#000] hover:shadow-[2px_2px_0_0_#000] hover:translate-x-0.5 hover:translate-y-0.5 transition-all mt-1">
            {loading ? 'Signing in…' : 'Sign in →'}
          </button>
        </form>
      </div>
    </div>
  )
}
