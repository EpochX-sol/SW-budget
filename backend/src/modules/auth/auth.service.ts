import { FastifyInstance } from 'fastify';
import {
  hashPassword,
  verifyPassword,
  generateRefreshToken,
  hashToken,
} from '../../utils/crypto.js';
import {
  authRepository,
  AuthRepository,
} from './auth.repository.js';
import {
  RegisterInput,
  LoginInput,
  RefreshInput,
  LogoutInput,
} from './auth.schemas.js';
import { env } from '../../config/env.js';

export class AuthService {
  constructor(private repo: AuthRepository = authRepository) {}

  async register(input: RegisterInput, fastify: FastifyInstance) {
    // 1. Check if user already exists
    const existing = await this.repo.findUserByEmail(input.email);
    if (existing) {
      const error: any = new Error('A user with this email address already exists');
      error.statusCode = 409;
      error.name = 'Conflict';
      throw error;
    }

    // 2. Hash password with Argon2id
    const passwordHash = await hashPassword(input.password);

    // 3. Generate rotating refresh token
    const { token: refreshToken, hash: refreshTokenHash } = generateRefreshToken();

    // 4. Create user, initial sync state, and device record in transaction
    const { user } = await this.repo.createUserWithDevice(
      {
        email: input.email,
        passwordHash,
        displayName: input.display_name,
        currency: input.currency,
        timezone: input.timezone,
        monthStartDay: input.month_start_day,
      },
      input.device,
      refreshTokenHash
    );

    // 5. Sign JWT access token (15 minutes)
    const accessToken = fastify.jwt.sign({
      id: user.id,
      email: user.email,
      deviceId: input.device.id,
    });

    return {
      access_token: accessToken,
      refresh_token: refreshToken,
      expires_in: env.JWT_EXPIRES_IN,
      user: {
        id: user.id,
        email: user.email,
        display_name: user.displayName,
        currency: user.currency,
        timezone: user.timezone,
        month_start_day: user.monthStartDay,
      },
    };
  }

  async login(input: LoginInput, fastify: FastifyInstance) {
    // 1. Find user by email
    const user = await this.repo.findUserByEmail(input.email);
    if (!user) {
      const error: any = new Error('Invalid email or password');
      error.statusCode = 401;
      error.name = 'Unauthorized';
      throw error;
    }

    // 2. Verify password with Argon2id
    const valid = await verifyPassword(user.passwordHash, input.password);
    if (!valid) {
      const error: any = new Error('Invalid email or password');
      error.statusCode = 401;
      error.name = 'Unauthorized';
      throw error;
    }

    // 3. Generate fresh rotating refresh token
    const { token: refreshToken, hash: refreshTokenHash } = generateRefreshToken();

    // 4. Upsert device record and update token hash
    await this.repo.upsertDeviceOnLogin(user.id, input.device, refreshTokenHash);

    // 5. Sign JWT access token
    const accessToken = fastify.jwt.sign({
      id: user.id,
      email: user.email,
      deviceId: input.device.id,
    });

    return {
      access_token: accessToken,
      refresh_token: refreshToken,
      expires_in: env.JWT_EXPIRES_IN,
      user: {
        id: user.id,
        email: user.email,
        display_name: user.displayName,
        currency: user.currency,
        timezone: user.timezone,
        month_start_day: user.monthStartDay,
      },
    };
  }

  async refresh(input: RefreshInput, fastify: FastifyInstance) {
    // 1. Find device
    const device = await this.repo.findDeviceById(input.device_id);
    if (!device || !device.user || device.user.deletedAt) {
      const error: any = new Error('Device session not found or revoked');
      error.statusCode = 401;
      error.name = 'Unauthorized';
      throw error;
    }

    // 2. Validate token hash
    const incomingHash = hashToken(input.refresh_token);

    if (!device.refreshTokenHash) {
      // Possible token reuse attack on an already revoked session
      await this.repo.revokeAllUserDevices(device.userId);
      const error: any = new Error('Session revoked due to security violation');
      error.statusCode = 401;
      error.name = 'Unauthorized';
      throw error;
    }

    if (device.refreshTokenHash !== incomingHash) {
      // Token mismatch / reuse attack detected: invalidate session immediately
      await this.repo.revokeDeviceToken(device.id);
      const error: any = new Error('Invalid refresh token. Token reuse detected');
      error.statusCode = 401;
      error.name = 'Unauthorized';
      throw error;
    }

    // 3. Rotate token: Issue new refresh token & new access token
    const { token: newRefreshToken, hash: newRefreshTokenHash } = generateRefreshToken();
    await this.repo.updateDeviceRefreshToken(device.id, newRefreshTokenHash);

    const accessToken = fastify.jwt.sign({
      id: device.user.id,
      email: device.user.email,
      deviceId: device.id,
    });

    return {
      access_token: accessToken,
      refresh_token: newRefreshToken,
      expires_in: env.JWT_EXPIRES_IN,
    };
  }

  async logout(input: LogoutInput, userId?: string) {
    if (userId) {
      const device = await this.repo.findDeviceById(input.device_id);
      if (device && device.userId !== userId) {
        const error: any = new Error('Unauthorized to logout this device');
        error.statusCode = 403;
        error.name = 'Forbidden';
        throw error;
      }
    }
    await this.repo.revokeDeviceToken(input.device_id);
    return { success: true };
  }

  async getMe(userId: string) {
    const user = await this.repo.findUserById(userId);
    if (!user) {
      const error: any = new Error('User not found');
      error.statusCode = 404;
      error.name = 'NotFound';
      throw error;
    }

    return {
      id: user.id,
      email: user.email,
      display_name: user.displayName,
      currency: user.currency,
      timezone: user.timezone,
      month_start_day: user.monthStartDay,
      sync_seq: Number(user.syncState?.seq ?? 0),
      created_at: user.createdAt,
      devices: user.devices,
    };
  }
}

export const authService = new AuthService();
