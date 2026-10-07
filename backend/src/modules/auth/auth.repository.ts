import { prisma } from '../../db/prisma.js';
import { DeviceInput } from './auth.schemas.js';

export interface CreateUserData {
  email: string;
  passwordHash: string;
  displayName?: string;
  currency: string;
  timezone: string;
  monthStartDay: number;
}

export class AuthRepository {
  async findUserByEmail(email: string) {
    return prisma.user.findFirst({
      where: {
        email,
        deletedAt: null,
      },
      include: {
        devices: true,
      },
    });
  }

  async findUserById(id: string) {
    return prisma.user.findFirst({
      where: {
        id,
        deletedAt: null,
      },
      include: {
        syncState: true,
        devices: {
          select: {
            id: true,
            deviceName: true,
            platform: true,
            appVersion: true,
            lastSeenAt: true,
          },
        },
      },
    });
  }

  async findDeviceById(deviceId: string) {
    return prisma.device.findUnique({
      where: { id: deviceId },
      include: { user: true },
    });
  }

  async createUserWithDevice(
    userData: CreateUserData,
    deviceData: DeviceInput,
    refreshTokenHash: string
  ) {
    return prisma.$transaction(async (tx) => {
      // 1. Create User
      const user = await tx.user.create({
        data: {
          email: userData.email,
          passwordHash: userData.passwordHash,
          displayName: userData.displayName,
          currency: userData.currency,
          timezone: userData.timezone,
          monthStartDay: userData.monthStartDay,
        },
      });

      // 2. Initialize User Sync State with sequence 0
      await tx.userSyncState.create({
        data: {
          userId: user.id,
          seq: 0n,
        },
      });

      // 3. Register Initial Device
      const device = await tx.device.create({
        data: {
          id: deviceData.id,
          userId: user.id,
          deviceName: deviceData.device_name,
          platform: deviceData.platform,
          appVersion: deviceData.app_version,
          fcmToken: deviceData.fcm_token,
          refreshTokenHash,
          lastSeenAt: new Date(),
        },
      });

      return { user, device };
    });
  }

  async upsertDeviceOnLogin(
    userId: string,
    deviceData: DeviceInput,
    refreshTokenHash: string
  ) {
    return prisma.device.upsert({
      where: { id: deviceData.id },
      create: {
        id: deviceData.id,
        userId,
        deviceName: deviceData.device_name,
        platform: deviceData.platform,
        appVersion: deviceData.app_version,
        fcmToken: deviceData.fcm_token,
        refreshTokenHash,
        lastSeenAt: new Date(),
      },
      update: {
        deviceName: deviceData.device_name,
        platform: deviceData.platform,
        appVersion: deviceData.app_version,
        fcmToken: deviceData.fcm_token || undefined,
        refreshTokenHash,
        lastSeenAt: new Date(),
      },
    });
  }

  async updateDeviceRefreshToken(deviceId: string, newRefreshTokenHash: string) {
    return prisma.device.update({
      where: { id: deviceId },
      data: {
        refreshTokenHash: newRefreshTokenHash,
        lastSeenAt: new Date(),
      },
    });
  }

  async revokeDeviceToken(deviceId: string) {
    return prisma.device.update({
      where: { id: deviceId },
      data: {
        refreshTokenHash: null,
        fcmToken: null,
      },
    });
  }

  async revokeAllUserDevices(userId: string) {
    return prisma.device.updateMany({
      where: { userId },
      data: {
        refreshTokenHash: null,
      },
    });
  }
}

export const authRepository = new AuthRepository();
