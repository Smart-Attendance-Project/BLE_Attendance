# Hosting Guide

## Backend → Render

1. Go to https://render.com → New → Web Service
2. Connect GitHub repo: `Smart-Attendance-Project/BLE_Attendance`
3. Branch: `feature/web-frontend`
4. Render auto-detects `render.yaml` → click **Apply**
5. Set env vars in Render dashboard:
   - `DATABASE_URL_OVERRIDE` → your Neon connection string (see below)
   - `JWT_SECRET` → auto-generated (already configured)
6. Deploy. API will be at `https://ble-attendance-api.onrender.com`

### Prevent spin-down (free tier)
- https://uptimerobot.com → Add Monitor
- Type: HTTP(s), URL: `https://ble-attendance-api.onrender.com/health`, Interval: 5 min

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
4. Add env var: `VITE_API_BASE_URL` = `https://ble-attendance-api.onrender.com`
5. Deploy. Done.

---

## Mobile App — build with hosted URL

```bash
cd mobile/ble_attendance_mobile
# Quick build:
API_BASE_URL=https://ble-attendance-api.onrender.com ./scripts/build.sh

# Or manually:
flutter build apk --release \
  --dart-define=API_BASE_URL=https://ble-attendance-api.onrender.com \
  --split-per-abi --target-platform android-arm,android-arm64
```
