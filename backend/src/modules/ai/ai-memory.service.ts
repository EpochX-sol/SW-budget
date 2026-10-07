import crypto from 'node:crypto';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { prisma } from '../../db/prisma.js';
import { env } from '../../config/env.js';

export class AiMemoryService {
  private genAI: GoogleGenerativeAI | null = null;

  constructor() {
    if (env.GEMINI_API_KEY && !env.GEMINI_API_KEY.startsWith('placeholder_') && env.GEMINI_API_KEY !== 'mock') {
      this.genAI = new GoogleGenerativeAI(env.GEMINI_API_KEY);
    }
  }

  /**
   * Generates a 768-dimensional embedding vector.
   * Uses Gemini text-embedding-004 when API key is provided, or a deterministic pseudo-random normalized vector.
   */
  async generateEmbedding(text: string): Promise<number[]> {
    if (this.genAI) {
      try {
        const model = this.genAI.getGenerativeModel({ model: 'text-embedding-004' });
        const result = await model.embedContent(text);
        if (result.embedding?.values && result.embedding.values.length === 768) {
          return result.embedding.values;
        }
      } catch (err) {
        console.warn('Gemini embedding API failed, falling back to deterministic local embedding:', err);
      }
    }

    // Deterministic 768-dimension normalized vector derived from text hash for testing & offline mode
    return this.generateDeterministicVector(text, 768);
  }

  private generateDeterministicVector(text: string, dim: number): number[] {
    const vec: number[] = new Array(dim).fill(0);
    const tokens = text.toLowerCase().replace(/[^a-z0-9\s]/g, ' ').split(/\s+/).filter(Boolean);

    // Feature hashing for semantic locality
    for (const token of tokens) {
      const hash = crypto.createHash('sha256').update(token).digest();
      for (let i = 0; i < 8; i++) {
        const idx = hash.readUInt16BE(i * 2) % dim;
        const sign = (hash[i] % 2 === 0) ? 1 : -1;
        vec[idx] += sign;
      }
    }

    let sumSq = 0;
    for (let i = 0; i < dim; i++) {
      sumSq += vec[i] * vec[i];
    }
    const norm = Math.sqrt(sumSq) || 1;
    return vec.map((v) => Number((v / norm).toFixed(6)));
  }

  /**
   * Stores a new memory item with pgvector embedding and contradiction resolution.
   */
  async addMemory(userId: string, input: {
    kind: 'goal' | 'habit' | 'preference' | 'fact' | 'decision';
    content: string;
    importance?: number;
    confidence?: number;
    pinned?: boolean;
    sourceMessageId?: string;
  }) {
    const memoryId = crypto.randomUUID();
    const embedding = await this.generateEmbedding(input.content);
    const vectorString = `[${embedding.join(',')}]`;

    // 1. Find candidates to supersede before inserting
    let candidatesToSupersede: string[] = [];
    if (input.kind === 'goal' || input.kind === 'preference') {
      const similar = await this.searchMemories(userId, input.content, 3);
      for (const candidate of similar) {
        if (candidate.kind === input.kind && candidate.similarity >= 0.70) {
          candidatesToSupersede.push(candidate.id);
        }
      }
    }

    // 2. Insert new memory first (so foreign key target exists)
    await prisma.$executeRawUnsafe(
      `INSERT INTO ai_memories (
        id, user_id, kind, content, embedding, importance, confidence, pinned, source_message_id, created_at
      ) VALUES ($1::uuid, $2::uuid, $3, $4, $5::vector, $6, $7, $8, $9::uuid, now())`,
      memoryId,
      userId,
      input.kind,
      input.content,
      vectorString,
      input.importance ?? 3,
      input.confidence ?? 0.8,
      input.pinned ?? false,
      input.sourceMessageId ?? null
    );

    // 3. Supersede prior memories with new memory ID
    for (const priorId of candidatesToSupersede) {
      await prisma.$executeRawUnsafe(
        `UPDATE ai_memories SET superseded_by = $1::uuid WHERE id = $2::uuid`,
        memoryId,
        priorId
      );
    }

    return {
      id: memoryId,
      user_id: userId,
      kind: input.kind,
      content: input.content,
      importance: input.importance ?? 3,
      confidence: input.confidence ?? 0.8,
      pinned: input.pinned ?? false,
      created_at: new Date().toISOString(),
    };
  }

  /**
   * Retrieves relevant memories using pgvector cosine distance and time-decay scoring.
   */
  async searchMemories(userId: string, queryText: string, limit = 8): Promise<any[]> {
    const embedding = await this.generateEmbedding(queryText);
    const vectorString = `[${embedding.join(',')}]`;

    const rows = await prisma.$queryRawUnsafe<any[]>(
      `SELECT id, kind, content, importance, confidence, pinned, created_at,
              (1 - (embedding <=> $1::vector)) AS similarity,
              ((1 - (embedding <=> $1::vector)) * EXP(-0.01 * EXTRACT(DAY FROM (now() - created_at)))) AS final_score
       FROM ai_memories
       WHERE user_id = $2::uuid
         AND deleted_at IS NULL
         AND superseded_by IS NULL
       ORDER BY final_score DESC
       LIMIT $3`,
      vectorString,
      userId,
      limit
    );

    return rows.map((r) => ({
      id: r.id,
      kind: r.kind,
      content: r.content,
      importance: Number(r.importance),
      confidence: Number(r.confidence),
      pinned: Boolean(r.pinned),
      created_at: r.created_at,
      similarity: Number(r.similarity),
      final_score: Number(r.final_score),
    }));
  }

  /**
   * Retrieves all non-deleted user memories for UI inspection.
   */
  async listMemories(userId: string) {
    return prisma.aiMemory.findMany({
      where: {
        userId,
        deletedAt: null,
      },
      orderBy: [{ pinned: 'desc' }, { createdAt: 'desc' }],
      select: {
        id: true,
        kind: true,
        content: true,
        importance: true,
        confidence: true,
        pinned: true,
        supersededBy: true,
        createdAt: true,
      },
    });
  }

  /**
   * Soft deletes a user memory.
   */
  async deleteMemory(userId: string, memoryId: string) {
    return prisma.aiMemory.updateMany({
      where: {
        id: memoryId,
        userId,
      },
      data: {
        deletedAt: new Date(),
      },
    });
  }
}

export const aiMemoryService = new AiMemoryService();
