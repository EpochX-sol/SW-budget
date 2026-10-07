import crypto from 'node:crypto';
import { FastifyReply } from 'fastify';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { prisma } from '../../db/prisma.js';
import { env } from '../../config/env.js';
import { financeTools, GEMINI_TOOL_DECLARATIONS } from './tools/finance-tools.js';
import { aiMemoryService } from './ai-memory.service.js';

const MONTHLY_TOKEN_LIMIT = 50000;

export class AiService {
  private genAI: GoogleGenerativeAI | null = null;

  constructor() {
    if (env.GEMINI_API_KEY && !env.GEMINI_API_KEY.startsWith('placeholder_') && env.GEMINI_API_KEY !== 'mock') {
      this.genAI = new GoogleGenerativeAI(env.GEMINI_API_KEY);
    }
  }

  /**
   * Enforces monthly token budget per user.
   */
  async checkTokenBudget(userId: string): Promise<number> {
    const month = new Date().toISOString().slice(0, 7); // YYYY-MM
    const usage = await prisma.aiUsage.findUnique({
      where: {
        userId_month: { userId, month },
      },
    });

    const consumed = usage ? usage.tokensConsumed : 0;
    if (consumed >= MONTHLY_TOKEN_LIMIT) {
      const err = new Error(
        `Monthly AI coaching budget reached (${MONTHLY_TOKEN_LIMIT.toLocaleString()} tokens). Quota resets on the 1st of next month.`
      );
      (err as any).statusCode = 429;
      throw err;
    }

    return consumed;
  }

  /**
   * Records token consumption into ai_usage.
   */
  async recordUsage(userId: string, tokens: number) {
    const month = new Date().toISOString().slice(0, 7);
    const costEstimate = (tokens / 1000000) * 0.15; // Gemini Flash est. $0.15/1M tokens

    await prisma.aiUsage.upsert({
      where: { userId_month: { userId, month } },
      create: {
        userId,
        month,
        tokensConsumed: tokens,
        costEstimateUsd: costEstimate,
      },
      update: {
        tokensConsumed: { increment: tokens },
        costEstimateUsd: { increment: costEstimate },
      },
    });
  }

  async getUsage(userId: string) {
    const month = new Date().toISOString().slice(0, 7);
    const usage = await prisma.aiUsage.findUnique({
      where: { userId_month: { userId, month } },
    });

    const consumed = usage ? usage.tokensConsumed : 0;
    return {
      month,
      tokens_consumed: consumed,
      monthly_limit: MONTHLY_TOKEN_LIMIT,
      percentage_used: Math.round((consumed / MONTHLY_TOKEN_LIMIT) * 100),
      resets_at: `${new Date(new Date().getFullYear(), new Date().getMonth() + 1, 1).toISOString().split('T')[0]}T00:00:00.000Z`,
    };
  }

  // ─────────────────────────────────────────────────────────────
  // Threads & Messages
  // ─────────────────────────────────────────────────────────────
  async createThread(userId: string, title?: string) {
    return prisma.aiThread.create({
      data: {
        userId,
        title: title || 'New Conversation',
      },
    });
  }

  async listThreads(userId: string) {
    return prisma.aiThread.findMany({
      where: { userId },
      orderBy: { updatedAt: 'desc' },
      include: {
        _count: {
          select: { messages: true },
        },
      },
    });
  }

  async getThreadMessages(userId: string, threadId: string) {
    const thread = await prisma.aiThread.findFirst({
      where: { id: threadId, userId },
    });
    if (!thread) {
      const err = new Error('Thread not found');
      (err as any).statusCode = 404;
      throw err;
    }

    return prisma.aiMessage.findMany({
      where: { threadId },
      orderBy: { createdAt: 'asc' },
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Streaming Chat Orchestration (SSE)
  // ─────────────────────────────────────────────────────────────
  async streamChat(userId: string, threadId: string, userContent: string, reply: FastifyReply) {
    // 1. Check Token Quota
    await this.checkTokenBudget(userId);

    // 2. Verify Thread
    const thread = await prisma.aiThread.findFirst({
      where: { id: threadId, userId },
    });
    if (!thread) {
      const err = new Error('Thread not found');
      (err as any).statusCode = 404;
      throw err;
    }

    // 3. Save User Message
    const userMsg = await prisma.aiMessage.create({
      data: {
        threadId,
        role: 'user',
        content: userContent,
      },
    });

    // 4. Initialize SSE Headers
    reply.raw.setHeader('Content-Type', 'text/event-stream');
    reply.raw.setHeader('Cache-Control', 'no-cache, no-transform');
    reply.raw.setHeader('Connection', 'keep-alive');
    reply.raw.setHeader('X-Accel-Buffering', 'no');

    const sendSse = (event: string, data: any) => {
      reply.raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };

    // 5. Retrieve Relevant Memories
    const relevantMemories = await aiMemoryService.searchMemories(userId, userContent, 4);

    let assistantText = '';
    let tokensUsed = 0;
    const toolCallsExecuted: any[] = [];

    try {
      // 6. Execute Conversation Flow (Gemini or Deterministic AI Simulator)
      if (this.genAI) {
        // Live Gemini Model Call with Function Calling
        const model = this.genAI.getGenerativeModel({
          model: 'gemini-1.5-flash',
          systemInstruction: this.buildSystemPrompt(relevantMemories),
          tools: [{ functionDeclarations: GEMINI_TOOL_DECLARATIONS as any }],
        });

        const chat = model.startChat();
        const response = await chat.sendMessage(userContent);
        const functionCalls = response.response.functionCalls();

        if (functionCalls && functionCalls.length > 0) {
          for (const call of functionCalls) {
            sendSse('tool_start', { tool: call.name, arguments: call.args });
            const toolResult = await this.executeTool(userId, call.name, call.args);
            sendSse('tool_end', { tool: call.name, result: toolResult });
            toolCallsExecuted.push({ tool: call.name, args: call.args, result: toolResult });

            // Send tool result back to Gemini
            const followUp = await chat.sendMessage([
              {
                functionResponse: {
                  name: call.name,
                  response: { result: toolResult },
                },
              },
            ]);

            const chunk = followUp.response.text();
            assistantText += chunk;
            sendSse('delta', { text: chunk });
          }
        } else {
          const chunk = response.response.text();
          assistantText = chunk;
          sendSse('delta', { text: chunk });
        }
        tokensUsed = 420; // Estimated turn tokens
      } else {
        // Deterministic Mathematical Simulator
        const simResult = await this.executeDeterministicSimulation(userId, userContent, sendSse);
        assistantText = simResult.text;
        tokensUsed = simResult.tokensUsed;
        toolCallsExecuted.push(...simResult.toolCalls);
      }

      // 7. Save Assistant Message
      const assistantMsg = await prisma.aiMessage.create({
        data: {
          threadId,
          role: 'assistant',
          content: assistantText,
          toolCalls: toolCallsExecuted.length > 0 ? toolCallsExecuted : undefined,
          tokensUsed,
        },
      });

      // Update thread timestamp
      await prisma.aiThread.update({
        where: { id: threadId },
        data: { updatedAt: new Date() },
      });

      // 8. Record Usage
      await this.recordUsage(userId, tokensUsed);

      // 9. Send SSE Done Event
      sendSse('done', {
        message_id: assistantMsg.id,
        tokens_used: tokensUsed,
      });
    } catch (err: any) {
      sendSse('error', { detail: err.message || 'Error generating AI response' });
    } finally {
      reply.raw.end();
    }
  }

  private buildSystemPrompt(memories: any[]): string {
    const memoryContext =
      memories.length > 0
        ? `\nRelevant user facts & goals:\n${memories.map((m) => `- [${m.kind}] ${m.content}`).join('\n')}`
        : '';

    return `You are SW-budget AI Financial Coach for Ethiopian users.
Your core principle: "Numbers from code, words from AI".
You NEVER compute arithmetic totals, monthly spending, or scenario forecasts in your head.
Whenever the user asks about money, budget, limits, or purchases, you MUST call one of the deterministic tools:
- get_spending_summary: for past expenditure and income
- simulate_scenario: for "can I afford" or prospective purchases
- get_budget_status: for limit status and percentage used
All currencies are ETB (Ethiopian Birr). Be encouraging, concise, and realistic.${memoryContext}`;
  }

  private async executeTool(userId: string, toolName: string, args: any) {
    if (toolName === 'get_spending_summary') {
      return financeTools.getSpendingSummary(userId, args);
    }
    if (toolName === 'simulate_scenario') {
      return financeTools.simulateScenario(userId, args);
    }
    if (toolName === 'get_budget_status') {
      return financeTools.getBudgetStatus(userId);
    }
    throw new Error(`Unknown tool: ${toolName}`);
  }

  /**
   * Deterministic local simulator when running in test / offline mode without API keys.
   */
  private async executeDeterministicSimulation(
    userId: string,
    userContent: string,
    sendSse: (event: string, data: any) => void
  ) {
    const lower = userContent.toLowerCase();
    const toolCalls: any[] = [];
    let text = '';

    // Match "afford" or prospective purchase
    const amountMatch = userContent.match(/(\d+[\d,]*(\.\d+)?)/);
    const amount = amountMatch ? parseFloat(amountMatch[1].replace(/,/g, '')) : null;

    if (amount !== null && (lower.includes('afford') || lower.includes('spend') || lower.includes('buy'))) {
      sendSse('tool_start', { tool: 'simulate_scenario', arguments: { amount } });
      const result = await financeTools.simulateScenario(userId, { amount });
      sendSse('tool_end', { tool: 'simulate_scenario', result });
      toolCalls.push({ tool: 'simulate_scenario', args: { amount }, result });

      if (result.has_limit && result.limit_breached) {
        text = `Spending ${result.proposed_amount.toLocaleString()} ETB will exceed your limit. You currently have ${result.remaining_before?.toLocaleString()} ETB remaining before hitting your ceiling. If you proceed, you will be in deficit by ${Math.abs(result.remaining_after || 0).toLocaleString()} ETB (approx ${result.days_in_deficit} days of spending allowance).`;
      } else if (result.has_limit) {
        text = `You can safely afford ${result.proposed_amount.toLocaleString()} ETB. You currently have ${result.remaining_before?.toLocaleString()} ETB available, and after this purchase you will still have ${result.remaining_after?.toLocaleString()} ETB remaining. Your safe daily budget for the remaining ${result.days_remaining_in_month} days will be ${result.safe_daily_budget_after?.toLocaleString()} ETB/day.`;
      } else {
        text = `You have spent ${result.current_spent.toLocaleString()} ETB this month. Adding ${result.proposed_amount.toLocaleString()} ETB brings your monthly total to ${result.simulated_total.toLocaleString()} ETB. No active spending limit is configured for this category.`;
      }
    } else if (lower.includes('budget') || lower.includes('limit') || lower.includes('status')) {
      sendSse('tool_start', { tool: 'get_budget_status', arguments: {} });
      const result = await financeTools.getBudgetStatus(userId);
      sendSse('tool_end', { tool: 'get_budget_status', result });
      toolCalls.push({ tool: 'get_budget_status', args: {}, result });

      if (result.active_limits.length === 0) {
        text = `You currently have no active budget limits set. Consider adding a monthly limit to keep your expenses on pace!`;
      } else {
        const summaries = result.active_limits.map(
          (l) => `${l.scope_name}: ${l.spent.toLocaleString()} / ${l.limit_amount.toLocaleString()} ETB (${l.percentage_used}% used, status: ${l.status})`
        );
        text = `Here is your budget status for ${result.month}:\n` + summaries.join('\n');
      }
    } else {
      // General spending summary
      sendSse('tool_start', { tool: 'get_spending_summary', arguments: { period: 'this_month' } });
      const result = await financeTools.getSpendingSummary(userId, { period: 'this_month' });
      sendSse('tool_end', { tool: 'get_spending_summary', result });
      toolCalls.push({ tool: 'get_spending_summary', args: { period: 'this_month' }, result });

      text = `This month you have spent a total of ${result.total_expense.toLocaleString()} ETB across ${result.transaction_count} transactions, with ${result.total_income.toLocaleString()} ETB in recorded income. Your net balance is ${result.net_savings.toLocaleString()} ETB.`;
    }

    // Stream text in 2-3 natural chunks
    const parts = text.match(/.{1,60}(\s|$)/g) || [text];
    for (const part of parts) {
      sendSse('delta', { text: part });
    }

    return {
      text,
      tokensUsed: 380,
      toolCalls,
    };
  }

  // ─────────────────────────────────────────────────────────────
  // Proposals
  // ─────────────────────────────────────────────────────────────
  async listProposals(userId: string) {
    return prisma.aiProposal.findMany({
      where: { userId, status: 'pending' },
      orderBy: { createdAt: 'desc' },
    });
  }

  async decideProposal(userId: string, proposalId: string, decision: 'accepted' | 'rejected') {
    const proposal = await prisma.aiProposal.findFirst({
      where: { id: proposalId, userId },
    });
    if (!proposal) {
      const err = new Error('Proposal not found');
      (err as any).statusCode = 404;
      throw err;
    }

    return prisma.aiProposal.update({
      where: { id: proposalId },
      data: {
        status: decision,
        decidedAt: new Date(),
      },
    });
  }
}

export const aiService = new AiService();
