import React, { createContext, useContext, useState, useEffect } from 'react'
import { login as apiLogin, getMe } from '../api/endpoints'

interface AuthUser { id: string; full_name: string; role: string; is_super_admin: boolean }
interface AuthCtx { user: AuthUser | null; login: (id: string, pw: string) => Promise<void>; logout: () => void }

const Ctx = createContext<AuthCtx>(null!)
export const useAuth = () => useContext(Ctx)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null)

  useEffect(() => {
    const token = localStorage.getItem('token')
    if (token) getMe().then(setUser).catch(() => localStorage.clear())
  }, [])

  const login = async (identifier: string, password: string) => {
    const data = await apiLogin(identifier, password)
    localStorage.setItem('token', data.access_token)
    const me = await getMe()
    setUser(me)
  }

  const logout = () => { localStorage.clear(); setUser(null) }

  return <Ctx.Provider value={{ user, login, logout }}>{children}</Ctx.Provider>
}
