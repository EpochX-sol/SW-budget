import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { spendingPlanService } from './spending-plan.service.js';
import {
  createPlanSchema,
  updatePlanSchema,
  simulatePlanSchema,
  createFixedExpenseSchema,
} from './spending-plan.schemas.js';

export const spendingPlanRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  // All plan routes require authentication
  fastify.addHook('preHandler', fastify.authenticate);

  // POST /v1/plans - Create new plan
  fastify.post('/v1/plans', async (request, reply) => {
    const input = createPlanSchema.parse(request.body);
    const result = await spendingPlanService.createPlan(request.user.id, input);
    return reply.status(201).send(result);
  });

  // GET /v1/plans/active - Get current active plan & snapshot
  fastify.get('/v1/plans/active', async (request, reply) => {
    const result = await spendingPlanService.getActivePlan(request.user.id);
    if (!result) {
      return reply.status(404).send({
        type: 'about:blank',
        title: 'Not Found',
        status: 404,
        detail: 'No active spending plan found',
      });
    }
    return reply.status(200).send(result);
  });

  // GET /v1/plans/:id - Get plan details
  fastify.get('/v1/plans/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const plan = await spendingPlanService.getPlanById(request.user.id, id);
    return reply.status(200).send({ plan });
  });

  // PATCH /v1/plans/:id - Update plan
  fastify.patch('/v1/plans/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const input = updatePlanSchema.parse(request.body);
    const result = await spendingPlanService.updatePlan(request.user.id, id, input);
    return reply.status(200).send(result);
  });

  // DELETE /v1/plans/:id - Archive/Delete plan
  fastify.delete('/v1/plans/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const result = await spendingPlanService.deletePlan(request.user.id, id);
    return reply.status(200).send(result);
  });

  // GET /v1/plans/:id/snapshot - Inspect snapshot
  fastify.get('/v1/plans/:id/snapshot', async (request, reply) => {
    const { id } = request.params as { id: string };
    await spendingPlanService.getPlanById(request.user.id, id);
    const snapshot = await spendingPlanService.recomputeSnapshot(id, request.user.id);
    return reply.status(200).send({ snapshot });
  });

  // GET /v1/plans/:id/weeks - Weekly breakdown with base & adjusted targets
  fastify.get('/v1/plans/:id/weeks', async (request, reply) => {
    const { id } = request.params as { id: string };
    await spendingPlanService.getPlanById(request.user.id, id);
    const snapshot = await spendingPlanService.recomputeSnapshot(id, request.user.id);
    return reply.status(200).send({ weeks: snapshot.weeks });
  });

  // POST /v1/plans/:id/simulate - "What if I spend X per day?"
  fastify.post('/v1/plans/:id/simulate', async (request, reply) => {
    const { id } = request.params as { id: string };
    const input = simulatePlanSchema.parse(request.body);
    const result = await spendingPlanService.simulateSpend(request.user.id, id, input);
    return reply.status(200).send(result);
  });

  // POST /v1/plans/:id/fixed-expenses - Add fixed commitment
  fastify.post('/v1/plans/:id/fixed-expenses', async (request, reply) => {
    const { id } = request.params as { id: string };
    const input = createFixedExpenseSchema.parse(request.body);
    const result = await spendingPlanService.addFixedExpense(request.user.id, id, input);
    return reply.status(201).send(result);
  });
};
