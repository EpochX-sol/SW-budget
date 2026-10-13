import { Redis } from 'ioredis';
import { env } from '../config/env.js';

export const redisConnection = new Redis(env.REDIS_URL, {
  maxRetriesPerRequest: null,
  enableReadyCheck: false,
  connectTimeout: 3000,
  commandTimeout: 2000,
  enableOfflineQueue: false, // Fail fast rather than queueing commands forever when offline
  retryStrategy(times) {
    if (times > 5) {
      // Back off if repeatedly failing
      return 10000;
    }
    return Math.min(times * 500, 3000);
  },
});

// Suppress unhandled error crashes when Redis is offline in cloud / dev environments
redisConnection.on('error', (err) => {
  // Silent or throttled log
});

export async function pingRedisWithTimeout(timeoutMs = 1500): Promise<boolean> {
  try {
    const pong = await Promise.race([
      redisConnection.ping(),
      new Promise<string>((_, reject) =>
        setTimeout(() => reject(new Error('Redis ping timeout')), timeoutMs)
      ),
    ]);
    return pong === 'PONG';
  } catch {
    return false;
  }
}

export async function safeRedisGet(key: string, timeoutMs = 1500): Promise<string | null> {
  try {
    const res = await Promise.race([
      redisConnection.get(key),
      new Promise<null>((_, reject) =>
        setTimeout(() => reject(new Error('Redis get timeout')), timeoutMs)
      ),
    ]);
    return res;
  } catch {
    return null;
  }
}

export async function safeRedisSetex(
  key: string,
  seconds: number,
  value: string,
  timeoutMs = 1500
): Promise<boolean> {
  try {
    await Promise.race([
      redisConnection.setex(key, seconds, value),
      new Promise<void>((_, reject) =>
        setTimeout(() => reject(new Error('Redis setex timeout')), timeoutMs)
      ),
    ]);
    return true;
  } catch {
    return false;
  }
}
