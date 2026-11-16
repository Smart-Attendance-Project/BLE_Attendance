import React, { createContext, useContext, useState, useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { SESSION_EXPIRED } from '../api/client'
import { login as apiLogin, logout as apiLogout, getMe } from '../api/endpoints'

interface AuthUser { id: string; full_name: string; role: string; is_super_admin: boolean }
interface AuthCtx { user: AuthUser | null; loading: boolean; login: (id: string, pw: string) => Promise<void>; logout: () => Promise<void> }

const Ctx = createContext<AuthCtx>(null!)
export const useAuth = () => useContext(Ctx)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null)
  const [loading, setLoading] = useState(true)
  const qc = useQueryClient()

  useEffect(() => {
    let active = true
    const onExpire = () => {
      setUser(null)
      qc.clear()
    }
    try {
      // Discard any token left behind by the previous frontend.
      localStorage.removeItem('token')
    } catch {
      // Web sessions do not require access to browser storage.
    }
    window.addEventListener(SESSION_EXPIRED, onExpire)
    getMe()
      .then(me => { if (active) setUser(me) })
      .catch(() => { if (active) setUser(null) })
      .finally(() => { if (active) setLoading(false) })
    return () => {
      active = false
      window.removeEventListener(SESSION_EXPIRED, onExpire)
    }
  }, [qc])

  const login = async (identifier: string, password: string) => {
    await apiLogin(identifier, password)
    const me = await getMe()
    setUser(me)
    qc.clear()
  }

  const logout = async () => {
    await apiLogout()
    setUser(null)
    qc.clear()
  }

  return <Ctx.Provider value={{ user, loading, login, logout }}>{children}</Ctx.Provider>
}
