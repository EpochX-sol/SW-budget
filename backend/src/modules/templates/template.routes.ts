import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { templateService } from './template.service.js';

export const templateRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  fastify.get('/v1/sms-templates', async (_request, reply) => {
    const bundle = await templateService.getSignedBundle();
    return reply.status(200).send(bundle);
  });

  // GET /v1/templates/patterns - Over-The-Air SMS regex patterns with ETag caching
  fastify.get('/v1/templates/patterns', async (request, reply) => {
    const bundle = await templateService.getPatternsBundle();
    const ifNoneMatch = request.headers['if-none-match'];

    if (ifNoneMatch && ifNoneMatch === bundle.etag) {
      return reply.status(304).send();
    }

    reply.header('ETag', bundle.etag);
    reply.header('Cache-Control', 'public, max-age=3600');
    return reply.status(200).send(bundle.payload);
  });
};

