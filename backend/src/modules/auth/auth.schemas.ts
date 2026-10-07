import { z } from 'zod';

export const deviceSchema = z.object({
  id: z.string().uuid({ message: 'Device ID must be a valid UUID' }),
  device_name: z.string().min(1, 'Device name is required').max(100),
  platform: z.enum(['android', 'ios', 'web']).default('android'),
  app_version: z.string().min(1, 'App version is required').max(20),
  fcm_token: z.string().optional(),
});

export const registerSchema = z.object({
  email: z.string().email('Invalid email address').toLowerCase().trim(),
  password: z
    .string()
    .min(8, 'Password must be at least 8 characters')
    .max(128, 'Password must be under 128 characters')
    .regex(/[A-Z]/, 'Password must contain at least one uppercase letter')
    .regex(/[a-z]/, 'Password must contain at least one lowercase letter')
    .regex(/[0-9]/, 'Password must contain at least one digit'),
  display_name: z.string().min(1).max(100).optional(),
  currency: z.string().length(3).default('ETB'),
  timezone: z.string().default('Africa/Addis_Ababa'),
  month_start_day: z.number().int().min(1).max(31).default(1),
  device: deviceSchema,
});

export const loginSchema = z.object({
  email: z.string().email('Invalid email address').toLowerCase().trim(),
  password: z.string().min(1, 'Password is required'),
  device: deviceSchema,
});

export const refreshSchema = z.object({
  refresh_token: z.string().min(10, 'Refresh token is required'),
  device_id: z.string().uuid('Device ID must be a valid UUID'),
});

export const logoutSchema = z.object({
  device_id: z.string().uuid('Device ID must be a valid UUID'),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput = z.infer<typeof loginSchema>;
export type RefreshInput = z.infer<typeof refreshSchema>;
export type LogoutInput = z.infer<typeof logoutSchema>;
export type DeviceInput = z.infer<typeof deviceSchema>;
