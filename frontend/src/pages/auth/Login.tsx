import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../../components/AuthContext'

export default function Login() {
  const { login, user } = useAuth()
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
      setErr('Invalid credentials')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{ maxWidth: 360, margin: '80px auto', padding: 24, border: '1px solid #ddd', borderRadius: 8 }}>
      <h2>BLE Attendance Login</h2>
      <form onSubmit={submit} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        <input placeholder="ID (T001 / ADMIN001 / 25CE001)" value={id} onChange={e => setId(e.target.value)} required />
        <input type="password" placeholder="Password" value={pw} onChange={e => setPw(e.target.value)} required />
        {err && <span style={{ color: 'red' }}>{err}</span>}
        <button type="submit" disabled={loading}>{loading ? 'Logging in…' : 'Login'}</button>
      </form>
    </div>
  )
}
