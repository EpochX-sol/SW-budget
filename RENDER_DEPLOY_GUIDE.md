# Render Deployment Guide: PostgreSQL & Fastify Backend

This guide provides complete instructions for deploying the **SW-budget** PostgreSQL database and Fastify backend API to [Render](https://render.com).

---

## Architecture Overview on Render

```
                                      ┌─────────────────────────────────────┐
                                      │        Render Cloud (Oregon/Frankfurt)│
                                      │                                     │
┌───────────────────────────┐         │  ┌───────────────────────────────┐  │
│   Flutter Mobile Client   │ ───────►│  │  Web Service: sw-budget-backend│ │
│  (Android / iOS / Web)    │  HTTPS  │  │  Fastify API (Port 10000/Node)│  │
└───────────────────────────┘         │  └───────┬───────────────┬───────┘  │
                                      │          │ (Internal)    │ (Internal)
                                      │          ▼               ▼          │
                                      │  ┌───────────────┐ ┌───────────────┐ │
                                      │  │ PostgreSQL 16 │ │ Redis Cache   │ │
                                      │  │ + pgvector    │ │ & BullMQ      │ │
                                      │  └───────────────┘ └───────────────┘ │
                                      └─────────────────────────────────────┘
```

---

## Prerequisites
1. A [GitHub](https://github.com) account with repository access: [`EpochX-sol/SW-budget`](https://github.com/EpochX-sol/SW-budget).
2. A free [Render account](https://render.com).
3. *(Recommended for Redis)* A free [Upstash](https://upstash.com) account (provides a 100% free serverless Redis instance with permanent persistence). Alternatively, you can use Render's managed Redis.

---

## Method 1: Manual Dashboard Setup (Recommended & Transparent)

### Step 1: Create PostgreSQL Database on Render

1. Log in to your [Render Dashboard](https://dashboard.render.com).
2. Click **New +** in the top right corner and select **PostgreSQL**.
3. Configure the database settings:
   - **Name:** `sw-budget-postgres`
   - **Database:** `sw_budget`
   - **User:** `sw`
   - **Region:** `Oregon (US West)` *(or choose Frankfurt if closer to your users)*
   - **PostgreSQL Version:** `16`
   - **Instance Type:** `Free`
4. Click **Create Database**.
5. Once created and status is **Available**:
   - Scroll to the **Connections** section.
   - Copy the **Internal Database URL** (e.g. `postgresql://sw:password@dpg-xxxx-a:5432/sw_budget`).  
     *(Use the Internal URL because your backend will run inside the same Render private network for maximum security and speed).*

> **Note on `pgvector`:** Render PostgreSQL 16 comes with `pgvector` and `pgcrypto` installed. Our Prisma migration script automatically runs `CREATE EXTENSION IF NOT EXISTS vector;` and `CREATE EXTENSION IF NOT EXISTS pgcrypto;` during deployment.

---

### Step 2: Set Up Redis (BullMQ & Cache)

The backend uses Redis for BullMQ background workers and caching.

#### Option A: Upstash Redis (100% Free Forever — Recommended)
1. Go to [Upstash Console](https://console.upstash.com) and sign in.
2. Click **Create Database**.
3. Name it `sw-budget-redis` and select the same region as your Render database (e.g. `US-East-1` or closest to Oregon).
4. Under the database details, scroll to **REST / Redis Connection URL**.
5. Copy the standard `redis://default:xxxx@xxxx.upstash.io:6379` connection string.

#### Option B: Render Managed Redis
1. In Render Dashboard, click **New +** → **Redis** (or **Key-Value**).
2. Set Name to `sw-budget-redis` and choose the same region.
3. Once provisioned, copy the **Internal Redis URL** (`redis://red-xxxx:6379`).

---

### Step 3: Deploy the Backend Web Service

1. In Render Dashboard, click **New +** and select **Web Service**.
2. Select **Build and deploy from a Git repository**.
3. Choose your repository: **`EpochX-sol/SW-budget`**.
4. Configure the service settings:
   - **Name:** `sw-budget-backend`
   - **Region:** Same region as your database (`Oregon (US West)`)
   - **Branch:** `main`
   - **Root Directory:** `backend` ⚠️ *(Crucial: set to `backend` since it is a monorepo!)*
   - **Runtime:** `Node`
   - **Build Command:**
     ```bash
     npm install && npx prisma generate && npm run build
     ```
   - **Start Command:**
     ```bash
     npx prisma migrate deploy && node dist/server.js
     ```
   - **Instance Type:** `Free`

5. Scroll down to **Environment Variables** and add the following keys:

| Key | Value | Description |
|---|---|---|
| `NODE_ENV` | `production` | Production mode |
| `HOST` | `0.0.0.0` | Listen on all network interfaces |
| `PORT` | `10000` | Render default HTTP port |
| `DATABASE_URL` | *Paste Internal Database URL from Step 1* | PostgreSQL connection string |
| `REDIS_URL` | *Paste Redis connection string from Step 2* | Redis connection string |
| `JWT_SECRET` | *(Generate a 32+ character random string)* | Access token signing secret |
| `JWT_REFRESH_SECRET` | *(Generate a 32+ character random string)* | Refresh token signing secret |
| `JWT_EXPIRES_IN` | `900` | Access token lifespan (seconds) |
| `TEMPLATE_SIGNING_PRIVATE_KEY` | `9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60` | Ed25519 hex signing key |
| `TEMPLATE_SIGNING_PUBLIC_KEY` | `d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a` | Ed25519 hex verification key |
| `LLM_PROVIDER` | `gemini` | AI Gateway provider |
| `GEMINI_API_KEY` | *(Your Google Gemini API Key)* | Optional for AI Chat module |

6. Click **Create Web Service**.

---

### Step 4: Verify Deployment & Health Check

1. Watch the **Deployment Logs** in Render. You should see:
   - `npm install` and TypeScript compilation `tsc`
   - `npx prisma migrate deploy` running migration `20261007000000_init_baseline` (enabling `vector` & `pgcrypto`)
   - Server starting: `Fastify server listening on http://0.0.0.0:10000`
2. Once the service status displays **Live**, copy your public URL (e.g., `https://sw-budget-backend.onrender.com`).
3. Test the health endpoint in your browser or curl:
   ```bash
   curl https://sw-budget-backend.onrender.com/health
   ```
   **Expected JSON output:**
   ```json
   {
     "status": "ok",
     "database": "connected",
     "redis": "connected"
   }
   ```
4. Access the Swagger interactive API docs:
   ```
   https://sw-budget-backend.onrender.com/documentation
   ```

---

### Step 5: Seed Default System Categories (One-Time)

To seed the initial expense and income categories (`Food & Groceries`, `Transport`, `Rent`, etc.):

1. In Render Dashboard, click your `sw-budget-backend` service.
2. Go to the **Shell** tab on the left.
3. Click **Start Shell** and run:
   ```bash
   npm run db:seed
   ```
4. You should see:
   ```text
   🌱 Seeding default system categories...
   ✔ System categories seeded successfully.
   ```

---

## Method 2: 1-Click Infrastructure Deployment (Render Blueprint)

A complete [render.yaml](render.yaml) configuration is provided in the repository root.

1. In Render Dashboard, click **New +** → **Blueprint**.
2. Connect your repository: `EpochX-sol/SW-budget`.
3. Render will parse `render.yaml` and show:
   - PostgreSQL database: `sw-budget-postgres`
   - Web Service: `sw-budget-backend`
4. Enter values for required secrets (`REDIS_URL` and optional `GEMINI_API_KEY`).
5. Click **Apply**. Render will provision and deploy everything automatically!

---

## Connecting the Flutter Mobile App to Render

Once your backend is live on Render:

### In Development (Running on Device or Emulator):
Pass the Render URL when running Flutter:
```powershell
cd mobile
flutter run --dart-define=API_BASE_URL=https://sw-budget-backend.onrender.com
```

### In Production / APK Release Build:
Build your Android APK pointing to Render:
```powershell
cd mobile
flutter build apk --release --dart-define=API_BASE_URL=https://sw-budget-backend.onrender.com
```
The generated APK will be at:
`mobile/build/app/outputs/flutter-apk/app-release.apk`

---

## Common Issues & Troubleshooting

### 1. Free Tier "Cold Start" Spin-down
On Render's Free tier, Web Services spin down after 15 minutes of inactivity. The first request after sleep may take ~30-50 seconds while the instance boots.
- **Tip:** In production, upgrade the web service to the $7/mo Starter plan for zero spin-down.
- **Alternative:** Set up a free ping monitor (such as [UptimeRobot](https://uptimerobot.com)) calling `https://your-service.onrender.com/health` every 10 minutes to keep it awake.

### 2. Error: `Cannot connect to Redis`
Ensure you used the **Internal Connection URL** if using Render Redis, or the full connection URL with port 6379 if using Upstash.

### 3. Error: `Root Directory not found`
Ensure the Web Service setting **Root Directory** is explicitly set to `backend` in the Render dashboard, because the repository root contains both `mobile/` and `backend/`.
