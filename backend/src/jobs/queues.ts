import { Queue } from 'bullmq';
import { redisConnection } from './redis.js';

export const outboxQueue = new Queue('outbox', {
  connection: redisConnection,
  defaultJobOptions: {
    attempts: 5,
    backoff: {
      type: 'exponential',
      delay: 1000,
    },
    removeOnComplete: 1000,
    removeOnFail: 5000,
  },
});

export const aggregatesQueue = new Queue('aggregates', {
  connection: redisConnection,
  defaultJobOptions: {
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: 500,
    },
    removeOnComplete: 500,
    removeOnFail: 2000,
  },
});

export const planSnapshotsQueue = new Queue('plan-snapshots', {
  connection: redisConnection,
  defaultJobOptions: {
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: 1000,
    },
    removeOnComplete: 500,
    removeOnFail: 2000,
  },
});

export const planNotificationsQueue = new Queue('plan-notifications', {
  connection: redisConnection,
  defaultJobOptions: {
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: 1000,
    },
    removeOnComplete: 500,
    removeOnFail: 2000,
  },
});

