import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { debtsService } from './debts.service.js';
import {
  createDebtSchema,
  updateDebtStatusSchema,
  recordRepaymentSchema,
} from './debts.schemas.js';

export const debtsRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  fastify.addHook('preHandler', fastify.authenticate);

  // GET /v1/finance/debts - List debts
  fastify.get('/v1/finance/debts', async (request, reply) => {
    const result = await debtsService.listDebts(request.user.id);
    return reply.status(200).send({ debts: result });
  });

  // POST /v1/finance/debts - Create new loan/debt
  fastify.post('/v1/finance/debts', async (request, reply) => {
    const input = createDebtSchema.parse(request.body);
    const result = await debtsService.createDebt(request.user.id, input);
    return reply.status(201).send(result);
  });

  // GET /v1/finance/debts/:id - Get debt details
  fastify.get('/v1/finance/debts/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const result = await debtsService.getDebtById(request.user.id, id);
    return reply.status(200).send({ debt: result });
  });

  // PATCH /v1/finance/debts/:id/status - Update debt status
  fastify.patch('/v1/finance/debts/:id/status', async (request, reply) => {
    const { id } = request.params as { id: string };
    const input = updateDebtStatusSchema.parse(request.body);
    const result = await debtsService.updateDebtStatus(request.user.id, id, input);
    return reply.status(200).send(result);
  });

  // POST /v1/finance/debts/:id/repayments - Record repayment
  fastify.post('/v1/finance/debts/:id/repayments', async (request, reply) => {
    const { id } = request.params as { id: string };
    const input = recordRepaymentSchema.parse(request.body);
    const result = await debtsService.recordRepayment(request.user.id, id, input);
    return reply.status(201).send(result);
  });
};
