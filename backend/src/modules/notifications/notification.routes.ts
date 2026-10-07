import { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { notificationService } from './notification.service.js';

const updatePreferencesSchema = z.object({
  enabled: z.boolean().optional(),
  quiet_start: z.string().regex(/^([01]\d|2[0-3]):([0-5]\d)$/).optional(),
  quiet_end: z.string().regex(/^([01]\d|2[0-3]):([0-5]\d)$/).optional(),
  show_amounts: z.boolean().optional(),
  daily_cap: z.number().int().min(1).max(20).optional(),
});

export const notificationRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.addHook('onRequest', fastify.authenticate);

  fastify.get('/v1/notifications', async (request, reply) => {
    const list = await notificationService.listNotifications(request.user.id);
    return reply.status(200).send(list);
  });

  fastify.patch('/v1/notifications/:id/read', async (request, reply) => {
    const { id } = request.params as { id: string };
    await notificationService.markAsRead(request.user.id, id);
    return reply.status(200).send({ success: true });
  });

  fastify.get('/v1/notifications/preferences', async (request, reply) => {
    const prefs = await notificationService.getPreferences(request.user.id);
    return reply.status(200).send(prefs);
  });

  fastify.put('/v1/notifications/preferences', async (request, reply) => {
    const parse = updatePreferencesSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({
        type: 'about:blank',
        title: 'Validation Error',
        status: 400,
        detail: parse.error.errors.map((e) => e.message).join(', '),
      });
    }

    const updated = await notificationService.updatePreferences(request.user.id, {
      ...(parse.data.enabled !== undefined && { enabled: parse.data.enabled }),
      ...(parse.data.quiet_start && { quietStart: parse.data.quiet_start }),
      ...(parse.data.quiet_end && { quietEnd: parse.data.quiet_end }),
      ...(parse.data.show_amounts !== undefined && { showAmounts: parse.data.show_amounts }),
      ...(parse.data.daily_cap !== undefined && { dailyCap: parse.data.daily_cap }),
    });

    return reply.status(200).send(updated);
  });
};
