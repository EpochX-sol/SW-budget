-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "email" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "display_name" TEXT,
    "currency" CHAR(3) NOT NULL DEFAULT 'ETB',
    "timezone" TEXT NOT NULL DEFAULT 'Africa/Addis_Ababa',
    "month_start_day" SMALLINT NOT NULL DEFAULT 1,
    "locale" TEXT NOT NULL DEFAULT 'en',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_sync_state" (
    "user_id" UUID NOT NULL,
    "seq" BIGINT NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_sync_state_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "devices" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "device_name" TEXT NOT NULL,
    "platform" TEXT NOT NULL DEFAULT 'android',
    "app_version" TEXT NOT NULL,
    "fcm_token" TEXT,
    "push_enabled" BOOLEAN NOT NULL DEFAULT true,
    "push_token_updated_at" TIMESTAMPTZ(6),
    "refresh_token_hash" TEXT,
    "last_seen_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "accounts" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "provider" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "account_mask" TEXT,
    "last_known_balance" DECIMAL(14,2),
    "balance_updated_at" TIMESTAMPTZ(6),
    "is_savings" BOOLEAN NOT NULL DEFAULT false,
    "change_seq" BIGINT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),

    CONSTRAINT "accounts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "categories" (
    "id" UUID NOT NULL,
    "user_id" UUID,
    "name" TEXT NOT NULL,
    "icon" TEXT NOT NULL,
    "color_hex" CHAR(7) NOT NULL,
    "is_system" BOOLEAN NOT NULL DEFAULT false,
    "change_seq" BIGINT NOT NULL,
    "deleted_at" TIMESTAMPTZ(6),

    CONSTRAINT "categories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "transactions" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "account_id" UUID NOT NULL,
    "category_id" UUID,
    "type" TEXT NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "balance_after" DECIMAL(14,2),
    "counterparty" TEXT,
    "reference" TEXT,
    "note" TEXT,
    "occurred_at" TIMESTAMPTZ(6) NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'sms',
    "parse_confidence" REAL,
    "template_id" TEXT,
    "balance_chain_ok" BOOLEAN,
    "gap_before_amount" DECIMAL(14,2),
    "is_internal_transfer" BOOLEAN NOT NULL DEFAULT false,
    "parent_txn_id" UUID,
    "dedupe_key" TEXT NOT NULL,
    "needs_review" BOOLEAN NOT NULL DEFAULT false,
    "user_edited_fields" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "change_seq" BIGINT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),

    CONSTRAINT "transactions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "limits" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "scope_type" TEXT NOT NULL DEFAULT 'overall',
    "scope_id" UUID,
    "period_type" TEXT NOT NULL,
    "start_date" DATE,
    "end_date" DATE,
    "amount" DECIMAL(14,2) NOT NULL,
    "mode" TEXT NOT NULL DEFAULT 'soft',
    "rollover" BOOLEAN NOT NULL DEFAULT false,
    "alert_thresholds" INTEGER[] DEFAULT ARRAY[50, 80, 100]::INTEGER[],
    "active" BOOLEAN NOT NULL DEFAULT true,
    "change_seq" BIGINT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),

    CONSTRAINT "limits_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "saving_plans" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "period_type" TEXT NOT NULL,
    "target_amount" DECIMAL(14,2) NOT NULL,
    "start_date" DATE NOT NULL,
    "end_date" DATE,
    "rule_type" TEXT NOT NULL,
    "rule_value" DECIMAL(14,2),
    "linked_account_id" UUID,
    "priority" SMALLINT NOT NULL DEFAULT 3,
    "status" TEXT NOT NULL DEFAULT 'active',
    "change_seq" BIGINT NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),

    CONSTRAINT "saving_plans_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "daily_category_totals" (
    "user_id" UUID NOT NULL,
    "day" DATE NOT NULL,
    "category_id" UUID NOT NULL,
    "account_id" UUID NOT NULL,
    "expense" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "income" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "fees" DECIMAL(14,2) NOT NULL DEFAULT 0,
    "txn_count" INTEGER NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "daily_category_totals_pkey" PRIMARY KEY ("user_id","day","category_id","account_id")
);

-- CreateTable
CREATE TABLE "notifications" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "channel" TEXT NOT NULL,
    "priority" TEXT NOT NULL DEFAULT 'normal',
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "data" JSONB NOT NULL DEFAULT '{}',
    "route" TEXT,
    "dedupe_key" TEXT,
    "delivery_status" TEXT NOT NULL DEFAULT 'pending',
    "sent_at" TIMESTAMPTZ(6),
    "read_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "notifications_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notification_preferences" (
    "user_id" UUID NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "categories" JSONB NOT NULL DEFAULT '{"limits":true,"daily":true,"savings":true,"bills":true,"insights":true,"sync":true,"security":true}',
    "quiet_start" TEXT NOT NULL DEFAULT '22:00',
    "quiet_end" TEXT NOT NULL DEFAULT '07:00',
    "morning_time" TEXT NOT NULL DEFAULT '07:30',
    "evening_time" TEXT,
    "digest_dow" SMALLINT NOT NULL DEFAULT 0,
    "digest_time" TEXT NOT NULL DEFAULT '18:00',
    "show_amounts" BOOLEAN NOT NULL DEFAULT false,
    "daily_cap" SMALLINT NOT NULL DEFAULT 5,
    "snoozed_until" TIMESTAMPTZ(6),

    CONSTRAINT "notification_preferences_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "user_schedules" (
    "user_id" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "next_run_at" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "user_schedules_pkey" PRIMARY KEY ("user_id","kind")
);

-- CreateTable
CREATE TABLE "outbox_events" (
    "id" BIGSERIAL NOT NULL,
    "user_id" UUID NOT NULL,
    "event_type" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "processed_at" TIMESTAMPTZ(6),

    CONSTRAINT "outbox_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ai_threads" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "title" TEXT NOT NULL DEFAULT 'New Conversation',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ai_threads_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ai_messages" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "thread_id" UUID NOT NULL,
    "role" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "tool_calls" JSONB,
    "tokens_used" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ai_messages_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ai_proposals" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decided_at" TIMESTAMPTZ(6),

    CONSTRAINT "ai_proposals_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ai_usage" (
    "id" BIGSERIAL NOT NULL,
    "user_id" UUID NOT NULL,
    "month" CHAR(7) NOT NULL,
    "tokens_consumed" INTEGER NOT NULL DEFAULT 0,
    "cost_estimate_usd" DECIMAL(10,4) NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ai_usage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ai_memories" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "embedding" vector(768),
    "importance" SMALLINT NOT NULL DEFAULT 3,
    "confidence" REAL NOT NULL DEFAULT 0.8,
    "pinned" BOOLEAN NOT NULL DEFAULT false,
    "source_message_id" UUID,
    "last_confirmed_at" TIMESTAMPTZ(6),
    "superseded_by" UUID,
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(6),

    CONSTRAINT "ai_memories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_log" (
    "id" BIGSERIAL NOT NULL,
    "user_id" UUID,
    "action" TEXT NOT NULL,
    "ip_address" TEXT,
    "user_agent" TEXT,
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE INDEX "devices_user_id_idx" ON "devices"("user_id");

-- CreateIndex
CREATE INDEX "accounts_user_id_idx" ON "accounts"("user_id");

-- CreateIndex
CREATE INDEX "categories_user_id_idx" ON "categories"("user_id");

-- CreateIndex
CREATE INDEX "transactions_user_id_occurred_at_idx" ON "transactions"("user_id", "occurred_at" DESC);

-- CreateIndex
CREATE INDEX "transactions_user_id_category_id_occurred_at_idx" ON "transactions"("user_id", "category_id", "occurred_at");

-- CreateIndex
CREATE INDEX "transactions_user_id_change_seq_idx" ON "transactions"("user_id", "change_seq");

-- CreateIndex
CREATE UNIQUE INDEX "transactions_user_id_dedupe_key_key" ON "transactions"("user_id", "dedupe_key");

-- CreateIndex
CREATE INDEX "limits_user_id_idx" ON "limits"("user_id");

-- CreateIndex
CREATE INDEX "saving_plans_user_id_idx" ON "saving_plans"("user_id");

-- CreateIndex
CREATE INDEX "daily_category_totals_user_id_day_idx" ON "daily_category_totals"("user_id", "day" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "notifications_user_id_dedupe_key_key" ON "notifications"("user_id", "dedupe_key");

-- CreateIndex
CREATE INDEX "user_schedules_next_run_at_idx" ON "user_schedules"("next_run_at");

-- CreateIndex
CREATE INDEX "outbox_events_id_idx" ON "outbox_events"("id");

-- CreateIndex
CREATE INDEX "ai_threads_user_id_idx" ON "ai_threads"("user_id");

-- CreateIndex
CREATE INDEX "ai_proposals_user_id_idx" ON "ai_proposals"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "ai_usage_user_id_month_key" ON "ai_usage"("user_id", "month");

-- CreateIndex
CREATE INDEX "ai_memories_user_id_idx" ON "ai_memories"("user_id");

-- CreateIndex
CREATE INDEX "audit_log_user_id_idx" ON "audit_log"("user_id");

-- CreateIndex
CREATE INDEX "audit_log_created_at_idx" ON "audit_log"("created_at" DESC);

-- AddForeignKey
ALTER TABLE "user_sync_state" ADD CONSTRAINT "user_sync_state_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "devices" ADD CONSTRAINT "devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "accounts" ADD CONSTRAINT "accounts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "categories" ADD CONSTRAINT "categories_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "accounts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "categories"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_parent_txn_id_fkey" FOREIGN KEY ("parent_txn_id") REFERENCES "transactions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "limits" ADD CONSTRAINT "limits_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "saving_plans" ADD CONSTRAINT "saving_plans_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "saving_plans" ADD CONSTRAINT "saving_plans_linked_account_id_fkey" FOREIGN KEY ("linked_account_id") REFERENCES "accounts"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_preferences" ADD CONSTRAINT "notification_preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_schedules" ADD CONSTRAINT "user_schedules_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "outbox_events" ADD CONSTRAINT "outbox_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ai_threads" ADD CONSTRAINT "ai_threads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ai_messages" ADD CONSTRAINT "ai_messages_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "ai_threads"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ai_proposals" ADD CONSTRAINT "ai_proposals_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ai_usage" ADD CONSTRAINT "ai_usage_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ai_memories" ADD CONSTRAINT "ai_memories_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ai_memories" ADD CONSTRAINT "ai_memories_superseded_by_fkey" FOREIGN KEY ("superseded_by") REFERENCES "ai_memories"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_log" ADD CONSTRAINT "audit_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Create pgvector HNSW index for high performance approximate cosine nearest neighbor search
CREATE INDEX IF NOT EXISTS "ai_memories_embedding_hnsw_idx" ON "ai_memories" USING hnsw (embedding vector_cosine_ops);


