import { buildApp } from './app.js';
import { env } from './config/env.js';
import { prisma } from './db/prisma.js';
import { redisConnection } from './jobs/redis.js';
import { createAggregatesWorker } from './jobs/workers/aggregates.worker.js';
import { schedulerWorker } from './jobs/workers/scheduler.worker.js';
import { createOutboxWorker, outboxRelay } from './jobs/workers/outbox.worker.js';

async function startServer() {
  const app = await buildApp();

  // Initialize BullMQ Workers
  const aggregatesWorker = createAggregatesWorker();
  const outboxWorker = createOutboxWorker();

  // Periodic intervals for background workers
  const schedulerInterval = setInterval(async () => {
    try {
      await schedulerWorker.runSchedulerCycle();
    } catch (err) {
      app.log.error(err, 'Scheduler tick failed');
    }
  }, 60_000);

  const outboxInterval = setInterval(async () => {
    try {
      await outboxRelay.relayPendingEvents();
    } catch (err) {
      app.log.error(err, 'Outbox relay tick failed');
    }
  }, 10_000);

  // Graceful shutdown handler
  const shutdown = async (signal: string) => {
    app.log.info(`Received ${signal}. Initiating graceful shutdown...`);

    clearInterval(schedulerInterval);
    clearInterval(outboxInterval);

    try {
      await aggregatesWorker.close();
      await outboxWorker.close();
      await app.close();
      await prisma.$disconnect();
      await redisConnection.quit();
      app.log.info('Graceful shutdown completed successfully.');
      process.exit(0);
    } catch (err) {
      app.log.error(err, 'Error during graceful shutdown');
      process.exit(1);
    }
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));

  try {
    const address = await app.listen({
      port: env.PORT,
      host: env.HOST,
    });
    app.log.info(`🚀 SW-budget API listening on ${address}`);
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

startServer();
