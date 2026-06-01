import { useState } from 'react'
import { changePassword } from '../../api/endpoints'

export default function ChangePassword() {
  const [oldPw, setOldPw] = useState('')
  const [newPw, setNewPw] = useState('')
  const [confirm, setConfirm] = useState('')
  const [loading, setLoading] = useState(false)
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null)

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (newPw !== confirm) { setMsg({ ok: false, text: 'New passwords do not match' }); return }
    setLoading(true); setMsg(null)
    try {
      await changePassword(oldPw, newPw)
      setMsg({ ok: true, text: 'Password changed successfully' })
      setOldPw(''); setNewPw(''); setConfirm('')
    } catch (e: any) {
      setMsg({ ok: false, text: e?.response?.data?.detail ?? 'Failed to change password' })
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="p-8 max-w-md mx-auto">
      <h1 className="text-3xl font-black text-zinc-900 mb-8">Change Password</h1>
      <form onSubmit={submit} className="bg-zinc-50 border-2 border-black rounded-xl p-6 shadow-[4px_4px_0_0_#000] flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <label className="text-sm font-bold text-zinc-700">Current Password</label>
          <input type="password" value={oldPw} onChange={e => setOldPw(e.target.value)} required
            className="border-2 border-black rounded-lg px-4 py-2.5 text-base focus:outline-none focus:ring-2 focus:ring-indigo-400 bg-white" />
        </div>
        <div className="flex flex-col gap-1">
          <label className="text-sm font-bold text-zinc-700">New Password</label>
          <input type="password" value={newPw} onChange={e => setNewPw(e.target.value)} required minLength={6}
            className="border-2 border-black rounded-lg px-4 py-2.5 text-base focus:outline-none focus:ring-2 focus:ring-indigo-400 bg-white" />
        </div>
        <div className="flex flex-col gap-1">
          <label className="text-sm font-bold text-zinc-700">Confirm New Password</label>
          <input type="password" value={confirm} onChange={e => setConfirm(e.target.value)} required minLength={6}
            className="border-2 border-black rounded-lg px-4 py-2.5 text-base focus:outline-none focus:ring-2 focus:ring-indigo-400 bg-white" />
        </div>
        {msg && (
          <p className={`text-sm font-semibold ${msg.ok ? 'text-green-700' : 'text-red-600'}`}>{msg.text}</p>
        )}
        <button type="submit" disabled={loading}
          className="bg-zinc-900 text-white font-bold py-3 rounded-xl border-2 border-black shadow-[3px_3px_0_0_#6366f1] hover:shadow-none hover:translate-x-0.5 hover:translate-y-0.5 transition-all disabled:opacity-50">
          {loading ? 'Saving…' : 'Change Password'}
        </button>
      </form>
    </div>
  )
}
