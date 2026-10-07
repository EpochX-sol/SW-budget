import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { templateService } from './template.service.js';

export const templateRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  fastify.get('/v1/sms-templates', async (_request, reply) => {
    const bundle = await templateService.getSignedBundle();
    return reply.status(200).send(bundle);
  });
};
