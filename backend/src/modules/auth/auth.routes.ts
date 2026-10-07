import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import {
  registerSchema,
  loginSchema,
  refreshSchema,
  logoutSchema,
} from './auth.schemas.js';
import { authService } from './auth.service.js';

export const authRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  // 1. User Registration
  fastify.post('/v1/auth/register', async (request, reply) => {
    const parseResult = registerSchema.safeParse(request.body);
    if (!parseResult.success) {
      return reply.status(400).send({
        type: 'about:blank',
        title: 'Validation Error',
        status: 400,
        detail: parseResult.error.errors.map((e) => e.message).join(', '),
        instance: request.url,
        timestamp: new Date().toISOString(),
      });
    }

    const result = await authService.register(parseResult.data, fastify);
    return reply.status(201).send(result);
  });

  // 2. User Login
  fastify.post('/v1/auth/login', async (request, reply) => {
    const parseResult = loginSchema.safeParse(request.body);
    if (!parseResult.success) {
      return reply.status(400).send({
        type: 'about:blank',
        title: 'Validation Error',
        status: 400,
        detail: parseResult.error.errors.map((e) => e.message).join(', '),
        instance: request.url,
        timestamp: new Date().toISOString(),
      });
    }

    const result = await authService.login(parseResult.data, fastify);
    return reply.status(200).send(result);
  });

  // 3. Token Refresh (Single-use rotation)
  fastify.post('/v1/auth/refresh', async (request, reply) => {
    const parseResult = refreshSchema.safeParse(request.body);
    if (!parseResult.success) {
      return reply.status(400).send({
        type: 'about:blank',
        title: 'Validation Error',
        status: 400,
        detail: parseResult.error.errors.map((e) => e.message).join(', '),
        instance: request.url,
        timestamp: new Date().toISOString(),
      });
    }

    const result = await authService.refresh(parseResult.data, fastify);
    return reply.status(200).send(result);
  });

  // 4. Logout
  fastify.post(
    '/v1/auth/logout',
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const parseResult = logoutSchema.safeParse(request.body);
      if (!parseResult.success) {
        return reply.status(400).send({
          type: 'about:blank',
          title: 'Validation Error',
          status: 400,
          detail: parseResult.error.errors.map((e) => e.message).join(', '),
          instance: request.url,
          timestamp: new Date().toISOString(),
        });
      }

      await authService.logout(parseResult.data, request.user.id);
      return reply.status(204).send();
    }
  );

  // 5. Authenticated User Profile
  fastify.get(
    '/v1/me',
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const user = request.user;
      const profile = await authService.getMe(user.id);
      return reply.status(200).send(profile);
    }
  );
};
