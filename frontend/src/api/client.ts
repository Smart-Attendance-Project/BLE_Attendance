import axios from 'axios'

export const SESSION_EXPIRED = 'attendance:session-expired'

const api = axios.create({
  baseURL: '/api',
  headers: { 'X-BLE-Web': '1' },
})

api.interceptors.response.use(
  response => response,
  error => {
    if (error.response?.status === 401 && error.config?.url !== '/auth/web/login') {
      window.dispatchEvent(new Event(SESSION_EXPIRED))
    }
    return Promise.reject(error)
  },
)

export default api
