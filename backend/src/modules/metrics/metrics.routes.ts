import { FastifyPluginAsync } from 'fastify';
import client from 'prom-client';

// Collect default system metrics (CPU, Memory, Event Loop)
client.collectDefaultMetrics({ prefix: 'sw_budget_' });

export const metricsRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.get('/metrics', async (_request, reply) => {
    const metrics = await client.register.metrics();
    reply.header('Content-Type', client.register.contentType);
    return reply.status(200).send(metrics);
  });
};
