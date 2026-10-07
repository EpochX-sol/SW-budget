import { FastifyPluginAsync } from 'fastify';
import { aiService } from './ai.service.js';
import { aiMemoryService } from './ai-memory.service.js';
import {
  createThreadSchema,
  sendMessageSchema,
  addMemorySchema,
  decideProposalSchema,
} from './ai.schemas.js';

export const aiRoutes: FastifyPluginAsync = async (fastify) => {
  // All AI routes require authentication
  fastify.addHook('onRequest', fastify.authenticate);

  // ─────────────────────────────────────────────────────────────
  // Threads & Chat
  // ─────────────────────────────────────────────────────────────
  fastify.post('/v1/ai/threads', async (request, reply) => {
    const parse = createThreadSchema.safeParse(request.body || {});
    if (!parse.success) {
      return reply.status(400).send({
        type: 'about:blank',
        title: 'Validation Error',
        status: 400,
        detail: parse.error.errors.map((e) => e.message).join(', '),
      });
    }

    const thread = await aiService.createThread(request.user.id, parse.data.title);
    return reply.status(201).send(thread);
  });

  fastify.get('/v1/ai/threads', async (request, reply) => {
    const threads = await aiService.listThreads(request.user.id);
    return reply.status(200).send(threads);
  });

  fastify.get('/v1/ai/threads/:id/messages', async (request, reply) => {
    const { id } = request.params as { id: string };
    const messages = await aiService.getThreadMessages(request.user.id, id);
    return reply.status(200).send(messages);
  });

  fastify.post('/v1/ai/threads/:id/messages', async (request, reply) => {
    const { id } = request.params as { id: string };
    const parse = sendMessageSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({
        type: 'about:blank',
        title: 'Validation Error',
        status: 400,
        detail: parse.error.errors.map((e) => e.message).join(', '),
      });
    }

    // Hands over reply raw stream to SSE handler
    await aiService.streamChat(request.user.id, id, parse.data.content, reply);
  });

  // ─────────────────────────────────────────────────────────────
  // Vector Memories
  // ─────────────────────────────────────────────────────────────
  fastify.get('/v1/ai/memories', async (request, reply) => {
    const memories = await aiMemoryService.listMemories(request.user.id);
    return reply.status(200).send({ memories });
  });

  fastify.post('/v1/ai/memories', async (request, reply) => {
    const parse = addMemorySchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({
        type: 'about:blank',
        title: 'Validation Error',
        status: 400,
        detail: parse.error.errors.map((e) => e.message).join(', '),
      });
    }

    const memory = await aiMemoryService.addMemory(request.user.id, parse.data);
    return reply.status(201).send(memory);
  });

  fastify.delete('/v1/ai/memories/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    await aiMemoryService.deleteMemory(request.user.id, id);
    return reply.status(204).send();
  });

  // ─────────────────────────────────────────────────────────────
  // Proposals & Token Usage
  // ─────────────────────────────────────────────────────────────
  fastify.get('/v1/ai/proposals', async (request, reply) => {
    const proposals = await aiService.listProposals(request.user.id);
    return reply.status(200).send(proposals);
  });

  fastify.post('/v1/ai/proposals/:id/decision', async (request, reply) => {
    const { id } = request.params as { id: string };
    const parse = decideProposalSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({
        type: 'about:blank',
        title: 'Validation Error',
        status: 400,
        detail: parse.error.errors.map((e) => e.message).join(', '),
      });
    }

    const proposal = await aiService.decideProposal(request.user.id, id, parse.data.decision);
    return reply.status(200).send(proposal);
  });

  fastify.get('/v1/ai/usage', async (request, reply) => {
    const usage = await aiService.getUsage(request.user.id);
    return reply.status(200).send(usage);
  });
};
