import { prisma } from '../../db/prisma.js';

export interface DispatchNotificationInput {
  userId: string;
  type:
    | 'limit_alert'
    | 'morning_allowance'
    | 'evening_summary'
    | 'bill_warning'
    | 'security_alert'
    | 'threshold_80'
    | 'allowance_exceeded'
    | 'burn_rate'
    | 'weekly_report'
    | 'plan_ending_soon'
    | 'plan_finished';
  channel: 'push' | 'in_app';
  priority?: 'normal' | 'high' | 'urgent';
  title: string;
  body: string;
  data?: Record<string, any>;
  route?: string;
  dedupeKey?: string;
  amount?: number;
}

export class NotificationService {
  /**
   * Dispatches a notification obeying quiet hours, daily caps, privacy masking, and deduplication.
   * Records strictly to PostgreSQL without external push services.
   */
  async dispatchNotification(input: DispatchNotificationInput) {
    const { userId, type, dedupeKey } = input;

    // 1. Check deduplication key (e.g. limit:food:2026-10:80)
    if (dedupeKey) {
      const existing = await prisma.notification.findUnique({
        where: {
          userId_dedupeKey: { userId, dedupeKey },
        },
      });
      if (existing) {
        return { dispatched: false, reason: 'duplicate_dedupe_key', notification: existing };
      }
    }

    // 2. Fetch or initialize notification preferences
    let prefs = await prisma.notificationPreference.findUnique({
      where: { userId },
    });

    if (!prefs) {
      prefs = await prisma.notificationPreference.create({
        data: { userId },
      });
    }

    // 3. Evaluate Quiet Hours (bypass for security_alert or urgent priority)
    if (prefs.enabled && input.priority !== 'urgent' && type !== 'security_alert') {
      const isQuiet = this.isQuietTime(prefs.quietStart, prefs.quietEnd);
      if (isQuiet) {
        return { dispatched: false, reason: 'quiet_hours_active' };
      }
    }

    // 4. Evaluate Daily Cap
    if (prefs.dailyCap > 0 && input.priority !== 'urgent') {
      const startOfDay = new Date();
      startOfDay.setHours(0, 0, 0, 0);

      const countToday = await prisma.notification.count({
        where: {
          userId,
          createdAt: { gte: startOfDay },
        },
      });

      if (countToday >= prefs.dailyCap) {
        return { dispatched: false, reason: 'daily_cap_exceeded' };
      }
    }

    // 5. Apply Lock-Screen Amount Privacy Masking
    let finalBody = input.body;
    if (!prefs.showAmounts && input.amount !== undefined) {
      finalBody = finalBody.replace(
        /ETB\s?[\d,]+(\.\d+)?|\d+[\d,]*(\.\d+)?\s?ETB/gi,
        'your configured limit'
      );
    }

    // 6. Record notification to in-app database
    const notification = await prisma.notification.create({
      data: {
        userId,
        type,
        channel: input.channel,
        priority: input.priority || 'normal',
        title: input.title,
        body: finalBody,
        data: input.data || {},
        route: input.route,
        dedupeKey: input.dedupeKey,
        deliveryStatus: 'delivered',
        sentAt: new Date(),
      },
    });

    return { dispatched: true, notification };
  }

  /**
   * Evaluates if current time falls within quiet hours (e.g. 22:00 to 07:00 spanning midnight).
   */
  isQuietTime(startStr: string, endStr: string, testTime?: Date): boolean {
    const now = testTime || new Date();
    const currentMinutes = now.getHours() * 60 + now.getMinutes();

    const [startH, startM] = startStr.split(':').map(Number);
    const [endH, endM] = endStr.split(':').map(Number);

    const startMinutes = startH * 60 + startM;
    const endMinutes = endH * 60 + endM;

    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      // Overnight quiet hours (e.g. 22:00 to 07:00)
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  }

  async markAsRead(userId: string, notificationId: string) {
    return prisma.notification.updateMany({
      where: { id: notificationId, userId },
      data: { readAt: new Date() },
    });
  }

  async markAllAsRead(userId: string) {
    return prisma.notification.updateMany({
      where: { userId, readAt: null },
      data: { readAt: new Date() },
    });
  }

  async listNotifications(userId: string, limit = 50, cursor?: string) {
    return prisma.notification.findMany({
      where: { userId },
      take: limit,
      skip: cursor ? 1 : 0,
      cursor: cursor ? { id: cursor } : undefined,
      orderBy: { createdAt: 'desc' },
    });
  }

  async getPreferences(userId: string) {
    return prisma.notificationPreference.upsert({
      where: { userId },
      create: { userId },
      update: {},
    });
  }

  async updatePreferences(
    userId: string,
    updates: Partial<{
      enabled: boolean;
      quietStart: string;
      quietEnd: string;
      showAmounts: boolean;
      dailyCap: number;
    }>
  ) {
    return prisma.notificationPreference.upsert({
      where: { userId },
      create: { userId, ...updates },
      update: updates,
    });
  }
}

export const notificationService = new NotificationService();
