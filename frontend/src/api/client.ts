import axios from 'axios'

// In production (Vercel), VITE_API_BASE_URL points to Render backend.
// In dev, /api is proxied to localhost:8000 via vite.config.ts.
const baseURL = import.meta.env.VITE_API_BASE_URL ?? '/api'

const api = axios.create({ baseURL })

api.interceptors.request.use(cfg => {
  const token = localStorage.getItem('token')
  if (token) cfg.headers.Authorization = `Bearer ${token}`
  return cfg
})

api.interceptors.response.use(
  r => r,
  err => {
    if (err.response?.status === 401) {
      localStorage.clear()
      window.location.href = '/login'
    }
    return Promise.reject(err)
  }
)

export default api
