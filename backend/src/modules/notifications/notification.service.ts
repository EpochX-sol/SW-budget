import crypto from 'node:crypto';
import { prisma } from '../../db/prisma.js';

import admin from 'firebase-admin';

let firebaseApp: admin.app.App | null = null;
if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
  try {
    const cred = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    firebaseApp = admin.initializeApp({ credential: admin.credential.cert(cred) }, 'sw-budget');
  } catch (err) {
    console.warn('Failed to parse FIREBASE_SERVICE_ACCOUNT_KEY:', err);
  }
}

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

    if (!prefs.enabled && input.priority !== 'urgent') {
      return { dispatched: false, reason: 'notifications_disabled' };
    }

    // 3. Evaluate quiet hours (e.g. 22:00 to 07:00; urgent security alerts bypass)
    if (input.priority !== 'urgent') {
      const isQuiet = this.isQuietTime(prefs.quietStart, prefs.quietEnd);
      if (isQuiet) {
        return { dispatched: false, reason: 'quiet_hours_active' };
      }
    }

    // 4. Evaluate daily non-urgent cap (default 5/day)
    if (input.priority !== 'urgent') {
      const todayStart = new Date();
      todayStart.setHours(0, 0, 0, 0);

      const countToday = await prisma.notification.count({
        where: {
          userId,
          createdAt: { gte: todayStart },
        },
      });

      if (countToday >= prefs.dailyCap) {
        return { dispatched: false, reason: 'daily_cap_exceeded' };
      }
    }

    // 5. Apply Lock-Screen Amount Privacy Masking
    let finalBody = input.body;
    if (!prefs.showAmounts && input.amount !== undefined) {
      // Replace sensitive amounts with generic privacy phrasing
      finalBody = finalBody.replace(
        /ETB\s?[\d,]+(\.\d+)?|\d+[\d,]*(\.\d+)?\s?ETB/gi,
        'your configured limit'
      );
    }

    // 6. Push delivery via Firebase Cloud Messaging if channel is push
    let deliveryStatus = 'delivered';
    if (input.channel === 'push') {
      const devices = await prisma.device.findMany({
        where: { userId, pushEnabled: true, fcmToken: { not: null } },
        select: { id: true, fcmToken: true },
      });

      const tokens = devices.map((d: { fcmToken: any; }) => d.fcmToken).filter(Boolean) as string[];

      if (tokens.length > 0 && firebaseApp) {
        try {
          const response = await firebaseApp.messaging().sendEachForMulticast({
            tokens,
            notification: {
              title: input.title,
              body: finalBody,
            },
            data: {
              type: input.type,
              route: input.route || '',
              ...(input.data ? Object.fromEntries(Object.entries(input.data).map(([k, v]) => [k, String(v)])) : {}),
            },
          });

          // Cleanup stale tokens
          for (let i = 0; i < response.responses.length; i++) {
            const resp = response.responses[i];
            if (!resp.success && resp.error?.code === 'messaging/registration-token-not-registered') {
              const staleDeviceId = devices[i]?.id;
              if (staleDeviceId) {
                await prisma.device.update({
                  where: { id: staleDeviceId },
                  data: { fcmToken: null },
                });
              }
            }
          }
        } catch (fcmErr) {
          console.warn('FCM dispatch failed, logging delivery as degraded:', fcmErr);
          deliveryStatus = 'degraded';
        }
      }
    }

    // 7. Record notification to in-app database
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
        deliveryStatus,
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

    const startMinutes = startH * 60 + (startM || 0);
    const endMinutes = endH * 60 + (endM || 0);

    if (startMinutes > endMinutes) {
      // Spans midnight (e.g., 22:00 - 07:00)
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    } else {
      // Within same day (e.g., 13:00 - 15:00)
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    }
  }

  async listNotifications(userId: string, limit = 50) {
    return prisma.notification.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });
  }

  async markAsRead(userId: string, notificationId: string) {
    return prisma.notification.updateMany({
      where: { id: notificationId, userId },
      data: { readAt: new Date() },
    });
  }

  async getPreferences(userId: string) {
    let prefs = await prisma.notificationPreference.findUnique({
      where: { userId },
    });
    if (!prefs) {
      prefs = await prisma.notificationPreference.create({
        data: { userId },
      });
    }
    return prefs;
  }

  async updatePreferences(userId: string, data: any) {
    return prisma.notificationPreference.upsert({
      where: { userId },
      create: { userId, ...data },
      update: data,
    });
  }
}

export const notificationService = new NotificationService();
