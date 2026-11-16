# Hosting Guide

## Backend → Render

1. Go to https://render.com → New → Web Service
2. Connect GitHub repo: `Smart-Attendance-Project/BLE_Attendance`
3. Branch: `feature/web-frontend`
4. Render auto-detects `render.yaml` → click **Apply**
5. Set env vars in Render dashboard:
   - `DATABASE_URL_OVERRIDE` → your Neon connection string (see below)
   - `JWT_SECRET` → auto-generated (already configured)
6. Deploy. API will be at `https://ble-attendance.onrender.com`

### Prevent spin-down (free tier)
- https://uptimerobot.com → Add Monitor
- Type: HTTP(s), URL: `https://ble-attendance.onrender.com/health`, Interval: 5 min

### Run seed after first deploy
In Render dashboard → your service → **Shell** tab:
```bash
PYTHONPATH=. python backend/scripts/seed_full.py
```

---

## Database → Neon (free Postgres, always-on)

1. https://neon.tech → Sign up → New Project → name: `ble-attendance`
2. Copy the **Connection string**: `postgresql://user:pass@ep-xxx.neon.tech/neondb?sslmode=require`
3. Change `postgresql://` → `postgresql+psycopg://`
4. Paste as `DATABASE_URL_OVERRIDE` in Render env vars

---

## Frontend → Vercel

1. https://vercel.com → New Project → Import from GitHub
2. Select `Smart-Attendance-Project/BLE_Attendance`
3. **Root Directory**: `frontend`
4. Set `WEB_ORIGINS` on the Render service to a JSON array of exact HTTPS frontend origins, for example `["https://attendance.example.com"]`. List each deployed frontend that should accept browser logins and omit trailing slashes. The production default is an empty allow-list.
5. Deploy the backend with `APP_ENV=production` and deploy the frontend. Vercel's `/api` rewrite forwards to the canonical Render host in `frontend/vercel.json`. Remove the obsolete frontend `VITE_API_BASE_URL` setting. A frontend deployed against a separate staging backend needs a matching rewrite target and its exact origin allow-listed on that backend.

The dashboard sends web authentication and API requests to its own origin. The proxy forwards the original `Origin` and `X-BLE-Web` headers for write validation. The backend creates the `browser_sessions` table at startup, stores only hashed session IDs, and issues 30-minute, Secure, HttpOnly, SameSite=Strict cookies. Signing out deletes the session from the database. The mobile app keeps its existing bearer-token flow.

Local Vite development proxies `/api` to `http://localhost:8000`. Run it at `http://localhost:5173` or `http://127.0.0.1:5173` with the backend in `APP_ENV=dev` for local HTTP cookies. If you use another local port, add its origin to `WEB_ORIGINS` explicitly.

After deployment, check that `/api/health` returns the API health response and the frontend sends its security headers. Sign in, reload the dashboard, then sign out and verify `/api/auth/me` returns 401. Use your browser console to check for CSP violations while navigating the dashboard.

---

## Mobile App — build with hosted URL

```bash
cd mobile/ble_attendance_mobile
# Quick build:
API_BASE_URL=https://ble-attendance.onrender.com ./scripts/build.sh

# Or manually:
flutter build apk --release \
  --dart-define=API_BASE_URL=https://ble-attendance.onrender.com \
  --split-per-abi --target-platform android-arm,android-arm64
```
