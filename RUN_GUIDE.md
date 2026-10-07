# SW-budget: Local Development & Emulator Run Guide

This guide provides step-by-step instructions for starting the backend infrastructure, the Fastify API server, and launching the Flutter mobile application inside the Android emulator.

---

## Architecture & Network Overview

```
┌─────────────────────────────────┐
│     Android Emulator            │
│  (Medium_Phone_API_37.0)        │
│                                 │
│  Flutter Mobile App             │
│  Calls: http://10.0.2.2:3000    │
└────────────────┬────────────────┘
                 │ (Loopback virtual network)
                 ▼
┌─────────────────────────────────┐
│       Windows Host Machine      │
│                                 │
│  Backend API: 0.0.0.0:3000      │
│  ├── PostgreSQL (Port 5432)     │
│  └── Redis 7    (Port 6379)     │
└─────────────────────────────────┘
```

> **Android Emulator Loopback Note:**  
> The Android emulator uses `10.0.2.2` as a special alias to access the host loopback (`127.0.0.1` / `localhost`). The mobile app in `mobile/lib/data/remote/api_endpoints.dart` already detects Android and connects to `http://10.0.2.2:3000` automatically.

---

## Quick Reference Commands

| Action | Command / Location |
|---|---|
| **Stop Backend** | Press `Ctrl + C` in the backend terminal or run the kill command |
| **Start Docker Infrastructure** | `docker compose up -d postgres redis` |
| **Start Backend API** | `cd backend` → `npm run dev` |
| **Launch Android Emulator** | `flutter emulators --launch Medium_Phone_API_37.0` |
| **Run Mobile App** | `cd mobile` → `flutter run` |

---

## Part 1: Managing the Backend Server

### 1.1 Stop Running Backend Servers
If a backend process or previous terminal session is occupying port 3000:

**In PowerShell:**
```powershell
# Check if any process is listening on port 3000
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq 3000 }

# Kill any process using port 3000
Get-NetTCPConnection -LocalPort 3000 -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```

---

### 1.2 Start Database & Redis (Docker)

1. **Launch Docker Desktop:**
   - Open **Docker Desktop** from the Windows Start menu (or run `Start-Process "C:\Users\$env:USERNAME\AppData\Local\Programs\DockerDesktop\Docker Desktop.exe"`).
   - Wait until the Docker engine indicator is green (running).

2. **Start PostgreSQL & Redis Containers:**
   From the repository root:
   ```powershell
   docker compose up -d postgres redis
   ```

3. **Verify Containers are Running:**
   ```powershell
   docker compose ps
   ```
   Both `sw_postgres` (port 5432) and `sw_redis` (port 6379) should show status **Up / healthy**.

---

### 1.3 Start the Fastify Backend Server

Open a dedicated terminal window:

```powershell
cd c:\Users\samue\OneDrive\Desktop\code\personal\SW-budget\backend

# 1. Install dependencies (if not done yet)
npm install

# 2. Synchronize Prisma database schema
npx prisma db push

# 3. Seed default system categories (optional, recommended on fresh DB)
npm run db:seed

# 4. Start the development server with live reload
npm run dev
```

**Verify Backend Health:**
Open your browser or run:
```powershell
curl http://localhost:3000/health
```
Expected response:
```json
{"status":"ok","database":"connected","redis":"connected"}
```

---

## Part 2: Starting the Mobile App in the Emulator

### 2.1 Launch the Android Emulator

Open a second terminal window (or start it directly via Android Studio Device Manager):

**Using Flutter CLI:**
```powershell
flutter emulators --launch Medium_Phone_API_37.0
```

**Alternative (Direct Emulator Binary):**
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd Medium_Phone_API_37.0
```

Wait until the Android OS completely boots to the home screen.

---

### 2.2 Verify Connected Devices

Check that Flutter detects the running emulator:
```powershell
flutter devices
```
You should see `emulator-5554` (or similar) listed as an online Android device.

---

### 2.3 Run the Flutter Application

From the `mobile/` directory:

```powershell
cd c:\Users\samue\OneDrive\Desktop\code\personal\SW-budget\mobile

# 1. Get dependencies
flutter pub get

# 2. Run on the emulator
flutter run
```

If multiple devices are detected, specify the emulator target:
```powershell
flutter run -d emulator-5554
```

> **Custom API Base URL (Optional):**  
> If you need to explicitly pass the API base URL:
> ```powershell
> flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:3000
> ```

---

## Part 3: Hot Reload & Useful Flutter Shortcuts

While `flutter run` is active in your terminal:
- Press **`r`**: Hot Reload (updates UI changes instantly).
- Press **`R`**: Hot Restart (restarts app state and reruns `main()`).
- Press **`v`**: Open Flutter DevTools in your browser.
- Press **`q`**: Quit the running mobile application.

---

## Troubleshooting

### Issue: "cmdline-tools component is missing" or "Android license status unknown"
If `flutter doctor` reports missing command line tools:
1. Open **Android Studio** → **Settings** (or **SDK Manager**).
2. Go to **Languages & Frameworks** → **Android SDK** → **SDK Tools** tab.
3. Check **Android SDK Command-line Tools (latest)** and click **Apply** / **OK**.
4. In PowerShell, accept licenses:
   ```powershell
   flutter doctor --android-licenses
   ```
   (Type `y` to accept all licenses).

### Issue: Mobile app cannot connect to backend (`Connection refused`)
1. Ensure the backend is listening on `0.0.0.0` (not only `127.0.0.1`). In `backend/src/server.ts`, this is set via `env.HOST` which defaults to `0.0.0.0`.
2. Confirm the emulator uses `http://10.0.2.2:3000`.
3. Test connectivity directly from the emulator via ADB:
   ```powershell
   adb shell curl http://10.0.2.2:3000/health
   ```

### Issue: Port 3000 already in use
```powershell
Get-NetTCPConnection -LocalPort 3000 -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```
