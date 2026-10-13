import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { prisma } from '../../db/prisma.js';

export const healthRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  fastify.get('/health', async (_request, reply) => {
    let dbStatus = 'down';
    let vectorStatus = 'down';

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

    const isCoreHealthy = dbStatus === 'up';

    return reply.status(isCoreHealthy ? 200 : 503).send({
      status: isCoreHealthy ? 'ok' : 'down',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      services: {
        database: dbStatus,
        vector_extension: vectorStatus,
      },
    });
  });
};
