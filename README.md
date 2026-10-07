# SW-budget

> An Android-first, AI-powered personal finance platform for Ethiopia. Reads Telebirr, CBE, and Bank of Abyssinia SMS & push notifications into a verified balance-chain ledger, enforces budgets, and powers an AI financial coach.

---

## Architecture Overview

- **Mobile:** Flutter (Android) · Riverpod · go_router · Drift (SQLCipher) · Kotlin SMS receiver & notification listener
- **Backend:** Node.js 22 · TypeScript · Fastify · PostgreSQL 16 + `pgvector` · Prisma ORM · BullMQ + Redis 7
- **AI Gateway:** Server-side LLM provider abstraction · Server-Sent Events (SSE) · Deterministic SQL tools · 768-dim vector memory

---

## Project Structure

```
SW-budget/
├── .agent/docs/design/              # Architectural specifications
│   ├── 2026-10-07-sw-budget-app-design.md
│   ├── backend/                     # Backend milestone designs (B1 - B4)
│   └── mobile/                      # Mobile milestone designs (F1 - F6)
├── docker-compose.yml               # PostgreSQL 16 (pgvector) & Redis 7
├── infra/postgres/init.sql          # DB extension initialization
├── backend/                         # Fastify modular monolith API
│   ├── prisma/schema.prisma         # Relational data schema
│   ├── src/                         # Server, config, plugins, modules
│   └── test/                        # Vitest integration suite
└── mobile/                          # Flutter client application
    ├── pubspec.yaml                 # Dependencies & asset configuration
    └── lib/                         # Feature-first application code
```

---

## Getting Started

> 📖 **Full step-by-step emulator and development guide:** [RUN_GUIDE.md](RUN_GUIDE.md)  
> 🚀 **Render Cloud Deployment Guide (Postgres & Backend):** [RENDER_DEPLOY_GUIDE.md](RENDER_DEPLOY_GUIDE.md)

### 1. Prerequisites
- Docker & Docker Compose
- Node.js LTS (v20+ or v22+)
- Flutter SDK (3.19+) & Android Studio

### 2. Start Infrastructure
```bash
cp .env.example .env
docker compose up -d
```
Verify PostgreSQL extensions:
```bash
docker exec sw_postgres psql -U sw -d sw_budget -c "\dx"
# Expected: vector (0.8.x) & pgcrypto (1.3)
```

### 3. Backend Setup & Run
```bash
cd backend
cp .env.example .env
npm install
npx prisma db push
npm test
npm run dev
```
Health endpoint: `http://localhost:3000/health`

### 4. Mobile App Setup
```bash
cd mobile
flutter pub get
flutter run
```

---

## API Documentation

Comprehensive API documentation with descriptions, request payloads, response bodies, and error codes is available at:
👉 **[API Reference Documentation](.agent/docs/api-documentation.md)**

