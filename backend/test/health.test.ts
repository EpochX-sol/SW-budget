import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { FastifyInstance } from 'fastify';
import supertest from 'supertest';
import { buildApp } from '../src/app.js';
import { prisma } from '../src/db/prisma.js';

describe('Health Check API', () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    app = await buildApp();
    await app.ready();
  });

  afterAll(async () => {
    await app.close();
    await prisma.$disconnect();
  });

  it('GET /health returns 200 with database and vector extension up', async () => {
    const res = await supertest(app.server).get('/health');

    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.services.database).toBe('up');
    expect(res.body.services.vector_extension).toBe('up');
  });
});
