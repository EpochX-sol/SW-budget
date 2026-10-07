import { FastifyInstance, FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import fastifyJwt from '@fastify/jwt';
import fp from 'fastify-plugin';
import { env } from '../config/env.js';

export interface JwtPayload {
  id: string;
  email: string;
  deviceId: string;
}

declare module 'fastify' {
  interface FastifyInstance {
    authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}

declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: JwtPayload;
    user: JwtPayload;
  }
}

const authPluginFn: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  await fastify.register(fastifyJwt, {
    secret: env.JWT_SECRET,
    sign: {
      expiresIn: `${env.JWT_EXPIRES_IN}s`,
    },
  });

  fastify.decorate(
    'authenticate',
    async (request: FastifyRequest, reply: FastifyReply): Promise<void> => {
      try {
        await request.jwtVerify();
      } catch (err) {
        return reply.status(401).send({
          type: 'about:blank',
          title: 'Unauthorized',
          status: 401,
          detail: 'Invalid or expired access token',
          instance: request.url,
          timestamp: new Date().toISOString(),
        });
      }
    }
  );
};

export const authPlugin = fp(authPluginFn, {
  name: 'auth-plugin',
});
