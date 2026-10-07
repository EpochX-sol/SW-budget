import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { prisma } from '../../db/prisma.js';
import { redisConnection } from '../../jobs/redis.js';

export const healthRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  fastify.get('/health', async (_request, reply) => {
    let dbStatus = 'down';
    let vectorStatus = 'down';
    let redisStatus = 'down';

    try {
      await prisma.$executeRawUnsafe('SELECT 1');
      dbStatus = 'up';

      // Verify vector extension exists
      const extensions: any = await prisma.$queryRawUnsafe(
        "SELECT extname FROM pg_extension WHERE extname = 'vector'"
      );
      if (Array.isArray(extensions) && extensions.length > 0) {
        vectorStatus = 'up';
      }
    } catch (error) {
      fastify.log.error(error, 'Health check DB query failed');
    }

    try {
      const pong = await redisConnection.ping();
      if (pong === 'PONG') {
        redisStatus = 'up';
      }
    } catch (error) {
      fastify.log.error(error, 'Health check Redis ping failed');
    }

    const isHealthy = dbStatus === 'up' && redisStatus === 'up';

    return reply.status(isHealthy ? 200 : 503).send({
      status: isHealthy ? 'ok' : 'degraded',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      services: {
        database: dbStatus,
        vector_extension: vectorStatus,
        redis: redisStatus,
      },
    });
  });
};
