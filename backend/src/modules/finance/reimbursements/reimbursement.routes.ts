import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { reimbursementService } from './reimbursement.service.js';
import { createReimbursementSchema } from './reimbursement.schemas.js';

export const reimbursementRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  fastify.addHook('preHandler', fastify.authenticate);

  // POST /v1/finance/reimbursements - Link credit txn to prior expense
  fastify.post('/v1/finance/reimbursements', async (request, reply) => {
    const input = createReimbursementSchema.parse(request.body);
    const result = await reimbursementService.createReimbursement(request.user.id, input);
    return reply.status(201).send(result);
  });

  // GET /v1/finance/reimbursements - List reimbursements
  fastify.get('/v1/finance/reimbursements', async (request, reply) => {
    const result = await reimbursementService.listReimbursements(request.user.id);
    return reply.status(200).send({ reimbursements: result });
  });

  // DELETE /v1/finance/reimbursements/:id - Unlink reimbursement
  fastify.delete('/v1/finance/reimbursements/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const result = await reimbursementService.deleteReimbursement(request.user.id, id);
    return reply.status(200).send(result);
  });
};
