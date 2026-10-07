import { FastifyPluginAsync } from 'fastify';
import { analyticsService } from './analytics.service.js';

export const analyticsRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.addHook('onRequest', fastify.authenticate);

  fastify.get('/v1/analytics/forecast', async (request, reply) => {
    const forecast = await analyticsService.getForecast(request.user.id);
    return reply.status(200).send(forecast);
  });

  fastify.get('/v1/analytics/trends', async (request, reply) => {
    const trends = await analyticsService.getTrends(request.user.id);
    return reply.status(200).send(trends);
  });

  fastify.get('/v1/analytics/fees', async (request, reply) => {
    const fees = await analyticsService.getFees(request.user.id);
    return reply.status(200).send(fees);
  });
};
