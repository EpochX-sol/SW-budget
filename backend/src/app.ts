import fastify, { FastifyError, FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import sensible from '@fastify/sensible';
import rateLimit from '@fastify/rate-limit';
import { authPlugin } from './plugins/auth.js';
import { healthRoutes } from './modules/health/health.routes.js';
import { authRoutes } from './modules/auth/auth.routes.js';
import { financeRoutes } from './modules/finance/finance.routes.js';
import { syncRoutes } from './modules/sync/sync.routes.js';
import { templateRoutes } from './modules/templates/template.routes.js';
import { aiRoutes } from './modules/ai/ai.routes.js';
import { notificationRoutes } from './modules/notifications/notification.routes.js';
import { analyticsRoutes } from './modules/analytics/analytics.routes.js';
import { exportRoutes } from './modules/export/export.routes.js';
import { metricsRoutes } from './modules/metrics/metrics.routes.js';
import { spendingPlanRoutes } from './modules/finance/spending-plan/spending-plan.routes.js';
import { reimbursementRoutes } from './modules/finance/reimbursements/reimbursement.routes.js';
import { debtsRoutes } from './modules/finance/debts/debts.routes.js';

// Polyfill BigInt JSON serialization for Fastify / Pino
(BigInt.prototype as any).toJSON = function () {
  return Number(this);
};

export async function buildApp(): Promise<FastifyInstance> {
  const app = fastify({
    bodyLimit: 15 * 1024 * 1024, // 15MB payload limit for backups & sync batches
    logger: {
      transport:
        process.env.NODE_ENV !== 'production'
          ? {
              target: 'pino-pretty',
              options: {
                translateTime: 'HH:MM:ss Z',
                ignore: 'pid,hostname',
              },
            }
          : undefined,
    },
  });

  // Security & utility plugins
  await app.register(helmet, { contentSecurityPolicy: false });
  await app.register(cors, {
    origin:
      process.env.NODE_ENV === 'production' && process.env.CORS_ALLOWED_ORIGINS
        ? process.env.CORS_ALLOWED_ORIGINS.split(',')
        : true,
  });
  await app.register(sensible);
  await app.register(rateLimit, {
    max: 100,
    timeWindow: '1 minute',
  });

  // Authentication plugin
  await app.register(authPlugin);

  // Global RFC 7807 problem details error handler
  app.setErrorHandler((error: FastifyError, request, reply) => {
    app.log.error(error);
    const statusCode = error.statusCode || 500;
    const isProd500 = process.env.NODE_ENV === 'production' && statusCode >= 500;
    return reply.status(statusCode).send({
      type: 'about:blank',
      title: error.name || 'Internal Server Error',
      status: statusCode,
      detail: isProd500 ? 'An unexpected internal error occurred' : error.message,
      instance: request.url,
      timestamp: new Date().toISOString(),
    });
  });

  // Modules registration
  await app.register(healthRoutes);
  await app.register(authRoutes);
  await app.register(financeRoutes);
  await app.register(syncRoutes);
  await app.register(templateRoutes);
  await app.register(aiRoutes);
  await app.register(notificationRoutes);
  await app.register(analyticsRoutes);
  await app.register(exportRoutes);
  await app.register(metricsRoutes);
  await app.register(spendingPlanRoutes);
  await app.register(reimbursementRoutes);
  await app.register(debtsRoutes);

  return app;
}
