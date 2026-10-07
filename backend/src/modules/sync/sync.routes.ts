import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { syncPushSchema, syncPullSchema } from './sync.schemas.js';
import { syncService } from './sync.service.js';

export const syncRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  fastify.addHook('preHandler', fastify.authenticate);

  // 1. Push Client Changes
  fastify.post('/v1/sync/push', async (request, reply) => {
    const parse = syncPushSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({
        type: 'about:blank',
        title: 'Validation Error',
        status: 400,
        detail: parse.error.errors.map((e) => e.message).join(', '),
      });
    }

    const idempotencyKey = request.headers['idempotency-key'] as string | undefined;
    const result = await syncService.pushChanges(request.user.id, parse.data, idempotencyKey);
    return reply.status(200).send(result);
  });

  // 2. Pull Server Changes by Monotonic Cursor
  fastify.get('/v1/sync/pull', async (request, reply) => {
    const parse = syncPullSchema.safeParse(request.query);
    if (!parse.success) {
      return reply.status(400).send({
        type: 'about:blank',
        title: 'Validation Error',
        status: 400,
        detail: parse.error.errors.map((e) => e.message).join(', '),
      });
    }

    const result = await syncService.pullChanges(request.user.id, parse.data);
    return reply.status(200).send(result);
  });

  // 3. Sync Status
  fastify.get('/v1/sync/status', async (request, reply) => {
    const result = await syncService.getStatus(request.user.id);
    return reply.status(200).send(result);
  });
};
