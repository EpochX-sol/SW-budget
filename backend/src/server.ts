import { buildApp } from './app.js';
import { env } from './config/env.js';
import { prisma } from './db/prisma.js';

async function startServer() {
  const app = await buildApp();

  // Graceful shutdown handler
  const shutdown = async (signal: string) => {
    app.log.info(`Received ${signal}. Initiating graceful shutdown...`);

    try {
      await app.close();
      await prisma.$disconnect();
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
