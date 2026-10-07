import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import {
  createAccountSchema,
  updateAccountSchema,
  createCategorySchema,
  updateCategorySchema,
  createLimitSchema,
  updateLimitSchema,
  createSavingPlanSchema,
  updateSavingPlanSchema,
  transactionQuerySchema,
  updateTransactionSchema,
  createTransactionSchema,
} from './finance.schemas.js';
import { financeService } from './finance.service.js';

export const financeRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  // All finance endpoints require authentication
  fastify.addHook('preHandler', fastify.authenticate);

  // ─────────────────────────────────────────────────────────────
  // Accounts
  // ─────────────────────────────────────────────────────────────
  fastify.get('/v1/accounts', async (request, reply) => {
    const accounts = await financeService.getAccounts(request.user.id);
    return reply.send(accounts);
  });

  fastify.post('/v1/accounts', async (request, reply) => {
    const parse = createAccountSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({ detail: parse.error.errors.map((e) => e.message).join(', ') });
    }
    const account = await financeService.createAccount(request.user.id, parse.data);
    return reply.status(201).send(account);
  });

  fastify.patch('/v1/accounts/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const parse = updateAccountSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({ detail: parse.error.errors.map((e) => e.message).join(', ') });
    }
    await financeService.updateAccount(request.user.id, id, parse.data);
    return reply.status(200).send({ success: true });
  });

  fastify.delete('/v1/accounts/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    await financeService.deleteAccount(request.user.id, id);
    return reply.status(204).send();
  });

  // ─────────────────────────────────────────────────────────────
  // Categories
  // ─────────────────────────────────────────────────────────────
  fastify.get('/v1/categories', async (request, reply) => {
    const categories = await financeService.getCategories(request.user.id);
    return reply.send(categories);
  });

  fastify.post('/v1/categories', async (request, reply) => {
    const parse = createCategorySchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({ detail: parse.error.errors.map((e) => e.message).join(', ') });
    }
    const category = await financeService.createCategory(request.user.id, parse.data);
    return reply.status(201).send(category);
  });

  fastify.patch('/v1/categories/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const parse = updateCategorySchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({ detail: parse.error.errors.map((e) => e.message).join(', ') });
    }
    await financeService.updateCategory(request.user.id, id, parse.data);
    return reply.status(200).send({ success: true });
  });

  fastify.delete('/v1/categories/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    await financeService.deleteCategory(request.user.id, id);
    return reply.status(204).send();
  });

  // ─────────────────────────────────────────────────────────────
  // Limits
  // ─────────────────────────────────────────────────────────────
  fastify.get('/v1/limits', async (request, reply) => {
    const limits = await financeService.getLimits(request.user.id);
    return reply.send(limits);
  });

  fastify.post('/v1/limits', async (request, reply) => {
    const parse = createLimitSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({ detail: parse.error.errors.map((e) => e.message).join(', ') });
    }
    const limit = await financeService.createLimit(request.user.id, parse.data);
    return reply.status(201).send(limit);
  });

  fastify.patch('/v1/limits/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const parse = updateLimitSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({ detail: parse.error.errors.map((e) => e.message).join(', ') });
    }
    await financeService.updateLimit(request.user.id, id, parse.data);
    return reply.status(200).send({ success: true });
  });

  fastify.delete('/v1/limits/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    await financeService.deleteLimit(request.user.id, id);
    return reply.status(204).send();
  });

  // ─────────────────────────────────────────────────────────────
  // Saving Plans
  // ─────────────────────────────────────────────────────────────
  fastify.get('/v1/saving-plans', async (request, reply) => {
    const plans = await financeService.getSavingPlans(request.user.id);
    return reply.send(plans);
  });

  fastify.post('/v1/saving-plans', async (request, reply) => {
    const parse = createSavingPlanSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({ detail: parse.error.errors.map((e) => e.message).join(', ') });
    }
    const plan = await financeService.createSavingPlan(request.user.id, parse.data);
    return reply.status(201).send(plan);
  });

  fastify.patch('/v1/saving-plans/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const parse = updateSavingPlanSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({ detail: parse.error.errors.map((e) => e.message).join(', ') });
    }
    await financeService.updateSavingPlan(request.user.id, id, parse.data);
    return reply.status(200).send({ success: true });
  });

  fastify.delete('/v1/saving-plans/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    await financeService.deleteSavingPlan(request.user.id, id);
    return reply.status(204).send();
  });

  // ─────────────────────────────────────────────────────────────
  // Transactions
  // ─────────────────────────────────────────────────────────────
  fastify.get('/v1/transactions', async (request, reply) => {
    const parse = transactionQuerySchema.safeParse(request.query);
    if (!parse.success) {
      return reply.status(400).send({ detail: parse.error.errors.map((e) => e.message).join(', ') });
    }
    const result = await financeService.getTransactions(request.user.id, parse.data);
    return reply.send(result);
  });

  fastify.post('/v1/transactions', async (request, reply) => {
    const parse = createTransactionSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({ detail: parse.error.errors.map((e) => e.message).join(', ') });
    }
    const txn = await financeService.createTransaction(request.user.id, parse.data);
    return reply.status(201).send(txn);
  });

  fastify.patch('/v1/transactions/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const parse = updateTransactionSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({ detail: parse.error.errors.map((e) => e.message).join(', ') });
    }
    await financeService.updateTransaction(request.user.id, id, parse.data);
    return reply.status(200).send({ success: true });
  });

  fastify.delete('/v1/transactions/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    await financeService.deleteTransaction(request.user.id, id);
    return reply.status(204).send();
  });
};
