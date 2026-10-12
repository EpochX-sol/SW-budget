import crypto from 'node:crypto';
import { FastifyReply } from 'fastify';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { prisma } from '../../db/prisma.js';
import { env } from '../../config/env.js';
import { financeTools, GEMINI_TOOL_DECLARATIONS, OPENAI_TOOL_DECLARATIONS } from './tools/finance-tools.js';
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
      // 6. Execute Conversation Flow (OpenRouter, Gemini, or Deterministic AI Simulator)
      const useOpenRouter = Boolean(
        env.OPENROUTER_API_KEY &&
        !env.OPENROUTER_API_KEY.startsWith('placeholder_') &&
        env.OPENROUTER_API_KEY !== 'mock'
      );

      if (useOpenRouter) {
        try {
          const previousMessages = await prisma.aiMessage.findMany({
            where: { threadId, id: { not: userMsg.id } },
            orderBy: { createdAt: 'desc' },
            take: 6,
          });
          previousMessages.reverse();

          const messages: any[] = [
            { role: 'system', content: this.buildSystemPrompt(relevantMemories) },
            ...previousMessages.map((m) => ({
              role: m.role === 'user' ? 'user' : 'assistant',
              content: m.content,
            })),
            { role: 'user', content: userContent },
          ];

          const openRouterUrl = `${env.OPENROUTER_BASE_URL.replace(/\/+$/, '')}/chat/completions`;
          const controller = new AbortController();
          const timeoutId = setTimeout(() => controller.abort(), 30000);

          const openRouterRes = await fetch(openRouterUrl, {
            method: 'POST',
            signal: controller.signal,
            headers: {
              'Authorization': `Bearer ${env.OPENROUTER_API_KEY}`,
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://sw-budget.local',
              'X-Title': 'SW-Budget AI Coach',
            },
            body: JSON.stringify({
              model: env.OPENROUTER_MODEL,
              messages,
              tools: OPENAI_TOOL_DECLARATIONS,
              tool_choice: 'auto',
              temperature: 0.2,
            }),
          }).finally(() => clearTimeout(timeoutId));

          if (!openRouterRes.ok) {
            const errText = await openRouterRes.text();
            throw new Error(`OpenRouter returned HTTP ${openRouterRes.status}: ${errText}`);
          }

          const completion = (await openRouterRes.json()) as any;
          const choice = completion.choices?.[0];
          const choiceMsg = choice?.message;

          if (choiceMsg?.tool_calls && choiceMsg.tool_calls.length > 0) {
            messages.push(choiceMsg);

            for (const call of choiceMsg.tool_calls) {
              const toolName = call.function.name;
              let toolArgs: any = {};
              try {
                toolArgs = JSON.parse(call.function.arguments || '{}');
              } catch (_) {}

              sendSse('tool_start', { tool: toolName, arguments: toolArgs });
              const toolResult = await this.executeTool(userId, toolName, toolArgs);
              sendSse('tool_end', { tool: toolName, result: toolResult });
              toolCallsExecuted.push({ tool: toolName, args: toolArgs, result: toolResult });

              messages.push({
                role: 'tool',
                tool_call_id: call.id,
                name: toolName,
                content: JSON.stringify(toolResult),
              });
            }

            // Stream follow-up from OpenRouter with tool outputs
            const followUpController = new AbortController();
            const followUpTimeout = setTimeout(() => followUpController.abort(), 30000);

            const followUpRes = await fetch(openRouterUrl, {
              method: 'POST',
              signal: followUpController.signal,
              headers: {
                'Authorization': `Bearer ${env.OPENROUTER_API_KEY}`,
                'Content-Type': 'application/json',
                'HTTP-Referer': 'https://sw-budget.local',
                'X-Title': 'SW-Budget AI Coach',
              },
              body: JSON.stringify({
                model: env.OPENROUTER_MODEL,
                messages,
                stream: true,
              }),
            }).finally(() => clearTimeout(followUpTimeout));

            if (followUpRes.ok && followUpRes.body) {
              const reader = followUpRes.body.getReader();
              const decoder = new TextDecoder();
              let streamDone = false;
              let buffer = '';

              while (!streamDone) {
                const { value, done: readerDone } = await reader.read();
                streamDone = readerDone;
                if (value) {
                  buffer += decoder.decode(value, { stream: !streamDone });
                  const lines = buffer.split('\n');
                  buffer = lines.pop() ?? '';

                  for (const line of lines) {
                    const trimmed = line.trim();
                    if (trimmed.startsWith('data:') && trimmed !== 'data: [DONE]') {
                      try {
                        const parsed = JSON.parse(trimmed.slice(5).trim());
                        const delta = parsed.choices?.[0]?.delta?.content || '';
                        if (delta) {
                          assistantText += delta;
                          sendSse('delta', { text: delta, content: delta, type: 'token' });
                        }
                      } catch (_) {}
                    }
                  }
                }
              }
            } else if (followUpRes.ok) {
              const followUpJson = (await followUpRes.json()) as any;
              const content = followUpJson.choices?.[0]?.message?.content || '';
              assistantText = content;
              sendSse('delta', { text: content, content, type: 'token' });
            } else {
              throw new Error(`Follow-up call returned HTTP ${followUpRes.status}`);
            }

            tokensUsed = 520;

            if (!assistantText || !assistantText.trim()) {
              console.warn('OpenRouter follow-up yielded empty text. Synthesizing from tool calls...');
              assistantText = this.synthesizeToolResults(userContent, toolCallsExecuted);
              const parts = assistantText.match(/.{1,60}(\s|$)/g) || [assistantText];
              for (const part of parts) {
                sendSse('delta', { text: part, content: part, type: 'token' });
              }
            }
          } else if (choiceMsg?.content && choiceMsg.content.trim()) {
            assistantText = choiceMsg.content;
            const parts = assistantText.match(/.{1,60}(\s|$)/g) || [assistantText];
            for (const part of parts) {
              sendSse('delta', { text: part, content: part, type: 'token' });
            }
            tokensUsed = completion.usage?.total_tokens || 350;
          } else {
            throw new Error('No content or tool calls returned by OpenRouter');
          }
        } catch (openRouterErr: any) {
          console.warn('OpenRouter call failed, engaging deterministic simulation fallback:', openRouterErr.message || openRouterErr);
          const simResult = await this.executeDeterministicSimulation(userId, userContent, sendSse);
          assistantText = simResult.text;
          tokensUsed = simResult.tokensUsed;
          toolCallsExecuted.push(...simResult.toolCalls);
        }

        if (!assistantText || !assistantText.trim()) {
          const simResult = await this.executeDeterministicSimulation(userId, userContent, sendSse);
          assistantText = simResult.text;
          tokensUsed = simResult.tokensUsed;
          toolCallsExecuted.push(...simResult.toolCalls);
        }
      } else if (this.genAI) {
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
            sendSse('delta', { text: chunk, content: chunk, type: 'token' });
          }
        } else {
          const chunk = response.response.text();
          assistantText = chunk;
          sendSse('delta', { text: chunk, content: chunk, type: 'token' });
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
        type: 'done',
        message_id: assistantMsg.id,
        tokens_used: tokensUsed,
        usage: { total_tokens: tokensUsed },
      });
    } catch (err: any) {
      sendSse('error', {
        type: 'error',
        detail: err.message || 'Error generating AI response',
        error: err.message || 'Error generating AI response',
      });
    } finally {
      reply.raw.end();
    }
  }

  private buildSystemPrompt(memories: any[]): string {
    const memoryContext =
      memories.length > 0
        ? `\n\n### USER PERSONAL MEMORY & CONTEXT (Episodic Facts)\n${memories.map((m) => `- [${m.kind.toUpperCase()}] ${m.content}`).join('\n')}\nUse these personal facts to customize advice naturally without explicitly announcing "according to your memory".`
        : '';

    return `### ROLE & MISSION
You are the SW-Budget AI Financial Coach — an empathetic, disciplined, and insightful personal finance advisor designed specifically for Ethiopian users. Your mission is to help users manage their money, build sustainable financial habits, understand their spending velocity, stay within monthly budget limits, and achieve their personal savings goals.

### THE CARDINAL RULE: "NUMBERS FROM CODE, WORDS FROM AI"
1. NEVER compute sums, balances, forecasts, or monthly totals in your head. Large Language Models hallucinate numbers. You must obtain ALL figures from tool calls.
2. Whenever the user asks about money, spending, affordability, limits, loans, or allowances, you MUST invoke one or more of the provided deterministic tools.
3. Once the tool returns the factual JSON, you interpret and contextualize the numbers in clear, structured, encouraging language.
4. Always state currency as ETB (Ethiopian Birr). Format figures with commas (e.g. 1,500 ETB, 25,000 ETB).

### TOOL INVOCATION HEURISTICS
Call the appropriate tool based on user intent:
1. "get_account_balances"
   - ALWAYS invoke this tool whenever the user asks "What is my balance?", "How much money do I have?", "Check my bank balance", or asks about CBE, Telebirr, Abyssinia, or Cash account balances.
   - NEVER ask the user what time period they want when asking for their balance. Invoke "get_account_balances" immediately.
2. "get_spending_summary" (period: 'today' | 'this_week' | 'this_month' | 'last_month')
   - When the user asks how much they spent, earned, or saved in a given timeframe.
   - For broad checks like "What is my financial situation?" or "How is my spending looking?".
3. "simulate_scenario" (amount: number, category_id?: string)
   - When the user asks "Can I afford X?", "Should I buy...", or asks about the impact of a prospective purchase.
   - Returns exact remaining balance before and after, safe daily budget, and deficit pace.
4. "get_budget_status"
   - When the user asks about budget limits, limit utilization percentages, or categories close to overspending.
5. "get_active_plan_snapshot"
   - When the user asks about their Adaptive Spending Plan, daily/weekly allowance, tomorrow's rollover allowance, pacing status, or streak.
6. "simulate_plan_spending" (proposed_spend_amount: number)
   - When the user asks how spending a particular daily amount affects their multi-day plan.
7. "query_loans_debts" (status?: 'active' | 'settled' | 'all', person_name?: string)
   - When the user asks who owes them money (lent) or what they owe to friends/family/banks (borrowed).
8. "query_reimbursements"
   - When the user asks about shared bills, group dinners, or pending reimbursements.

### LOCAL ETHIOPIAN FINANCIAL CONTEXT
- Understand Ethiopian cost realities: daily essentials (buna/coffee ceremonies, injera, grocery staples), transport (Bajaj, minibus taxi, Ride/Feres), housing rent, and traditional financial networks (Equb, Iddir, family remittances).
- Treat inflation and purchasing power respectfully; focus on cash-flow discipline and practical margin of safety.
- Language: Respond in the language used by the user. If the user writes in English, reply in English. If the user writes in Amharic (ሀ, ሁ, etc.), reply fluently in Amharic while retaining precise numbers and ETB currency.

### COMMUNICATION & COACHING STYLE
1. **Empathetic & Non-Judgmental**: Never shame the user for overspending. Acknowledge deficits with calm, proactive steps to recover (e.g., "You exceeded your dining budget by 400 ETB, but we can balance this by trimming discretionary spend by 100 ETB/day over the next 4 days.").
2. **Concise & Scannable**: Format answers with short paragraphs, clear bullet points, and **bold key numbers**. Mobile screens have limited space; avoid walls of uninterrupted text.
3. **Action-Oriented**: Conclude each response with 1 concrete recommendation or a helpful follow-up question.
4. **Safety & Privacy**: Never ask for or store passwords, PINs, or bank credentials. All financial math is computed securely on the user's private ledger.${memoryContext}`;
  }

  private async executeTool(userId: string, toolName: string, args: any) {
    if (toolName === 'get_account_balances') {
      return financeTools.getAccountBalances(userId);
    }
    if (toolName === 'get_spending_summary') {
      return financeTools.getSpendingSummary(userId, args);
    }
    if (toolName === 'simulate_scenario') {
      return financeTools.simulateScenario(userId, args);
    }
    if (toolName === 'get_budget_status') {
      return financeTools.getBudgetStatus(userId);
    }
    if (toolName === 'get_active_plan_snapshot') {
      return financeTools.getActivePlanSnapshot(userId);
    }
    if (toolName === 'simulate_plan_spending') {
      return financeTools.simulatePlanSpending(userId, args);
    }
    if (toolName === 'query_loans_debts') {
      return financeTools.queryLoansDebts(userId, args);
    }
    if (toolName === 'query_reimbursements') {
      return financeTools.queryReimbursements(userId, args);
    }
    throw new Error(`Unknown tool: ${toolName}`);
  }

  private synthesizeToolResults(userContent: string, toolCalls: any[]): string {
    if (!toolCalls || toolCalls.length === 0) {
      return "I analyzed your request, but could not retrieve matching financial data. Please ensure your accounts or transactions are recorded.";
    }

    const messages: string[] = [];
    for (const call of toolCalls) {
      const { tool, result } = call;
      if (!result) continue;

      if (tool === 'get_account_balances') {
        if (result.has_accounts) {
          const lines = result.accounts.map(
            (a: any) => `- **${a.name}** (${a.provider}${a.account_mask ? ' ' + a.account_mask : ''}): **${Number(a.balance).toLocaleString()} ETB**`
          );
          messages.push(`Your total balance is **${Number(result.total_balance).toLocaleString()} ETB** (Liquid: ${Number(result.total_liquid_balance).toLocaleString()} ETB, Savings: ${Number(result.total_savings_balance).toLocaleString()} ETB):\n\n` + lines.join('\n'));
        } else if (result.has_transactions) {
          messages.push(`Across your recorded transactions, your net balance is **${Number(result.all_time_net_savings).toLocaleString()} ETB** (Total Income: ${Number(result.total_recorded_income).toLocaleString()} ETB, Total Expenses: ${Number(result.total_recorded_expense).toLocaleString()} ETB).`);
        } else {
          messages.push(`You currently have no recorded bank accounts or transactions in SW-budget. Connect SMS tracking or record accounts to track your balances.`);
        }
      } else if (tool === 'get_spending_summary') {
        messages.push(`For the period **${result.period}**, your total spending is **${Number(result.total_expense).toLocaleString()} ETB** across ${result.transaction_count} transactions, with **${Number(result.total_income).toLocaleString()} ETB** in income (Net: **${Number(result.net_savings).toLocaleString()} ETB**).`);
      } else if (tool === 'simulate_scenario') {
        if (result.has_limit && result.limit_breached) {
          messages.push(`Spending **${Number(result.proposed_amount).toLocaleString()} ETB** will exceed your monthly limit! You have ${Number(result.remaining_before).toLocaleString()} ETB remaining before exceeding.`);
        } else if (result.has_limit) {
          messages.push(`You can safely spend **${Number(result.proposed_amount).toLocaleString()} ETB**. Remaining allowance will be ${Number(result.remaining_after).toLocaleString()} ETB.`);
        } else {
          messages.push(`Adding **${Number(result.proposed_amount).toLocaleString()} ETB** brings your total to ${Number(result.simulated_total).toLocaleString()} ETB.`);
        }
      } else if (tool === 'get_budget_status') {
        if (result.active_limits && result.active_limits.length > 0) {
          const lines = result.active_limits.map(
            (l: any) => `- **${l.scope_name}**: ${Number(l.spent).toLocaleString()} / ${Number(l.limit_amount).toLocaleString()} ETB (${l.percentage_used}% used)`
          );
          messages.push(`Here is your budget status for **${result.month}**:\n` + lines.join('\n'));
        } else {
          messages.push(`You currently have no active budget limits configured.`);
        }
      } else if (tool === 'get_active_plan_snapshot') {
        if (result.has_active_plan) {
          messages.push(`Your active plan is **"${result.plan_name}"**. Today's allowance: **${result.allowance_today} ETB** (${result.spent_today} ETB spent). Tomorrow's allowance: **${result.tomorrow_allowance} ETB**.`);
        } else {
          messages.push(`You do not have an active spending plan configured yet.`);
        }
      } else if (tool === 'query_loans_debts') {
        messages.push(`You have lent **${result.total_lent} ETB** and borrowed **${result.total_borrowed} ETB** across ${result.debts?.length || 0} active records.`);
      }
    }

    return messages.length > 0 ? messages.join('\n\n') : "I processed your financial query. Let me know if you would like more details!";
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

    if (lower.includes('balance') || lower.includes('bank') || lower.includes('cbe') || lower.includes('telebirr') || lower.includes('account') || lower.includes('money') || lower.includes('funds')) {
      sendSse('tool_start', { tool: 'get_account_balances', arguments: {} });
      const res = await financeTools.getAccountBalances(userId);
      sendSse('tool_end', { tool: 'get_account_balances', result: res });
      toolCalls.push({ tool: 'get_account_balances', args: {}, result: res });

      if (res.has_accounts) {
        const lines = res.accounts.map(
          (a: any) => `- **${a.name}** (${a.provider}${a.account_mask ? ' ' + a.account_mask : ''}): **${a.balance.toLocaleString()} ETB**`
        );
        text = `Your total balance is **${res.total_balance.toLocaleString()} ETB** (Liquid: ${res.total_liquid_balance.toLocaleString()} ETB, Savings: ${res.total_savings_balance.toLocaleString()} ETB):\n\n` + lines.join('\n');
      } else if (res.has_transactions) {
        text = `Across your recorded transactions, your net balance is **${res.all_time_net_savings.toLocaleString()} ETB** (Total Income: ${res.total_recorded_income.toLocaleString()} ETB, Total Expenses: ${res.total_recorded_expense.toLocaleString()} ETB).`;
      } else {
        text = `You currently have no recorded bank accounts or transactions in SW-budget. Connect SMS tracking or record accounts to track your balances.`;
      }
    } else if (lower.includes('plan') || lower.includes('allowance') || lower.includes('tomorrow')) {
      sendSse('tool_start', { tool: 'get_active_plan_snapshot', arguments: {} });
      const snap = await financeTools.getActivePlanSnapshot(userId);
      sendSse('tool_end', { tool: 'get_active_plan_snapshot', result: snap });
      toolCalls.push({ tool: 'get_active_plan_snapshot', args: {}, result: snap });

      if (!snap.has_active_plan) {
        text = 'You do not have an active spending plan configured yet. Create one to get daily allowances!';
      } else {
        text = `Your active plan is "${snap.plan_name}". Today's allowance is ${snap.allowance_today} ETB (${snap.spent_today} ETB spent). Tomorrow's allowance is adjusted to ${snap.tomorrow_allowance} ETB. Pacing status is ${snap.status} with a ${snap.streak}-day streak!`;
      }
    } else if (lower.includes('owe') || lower.includes('lent') || lower.includes('borrow') || lower.includes('debt')) {
      sendSse('tool_start', { tool: 'query_loans_debts', arguments: {} });
      const debts = await financeTools.queryLoansDebts(userId, {});
      sendSse('tool_end', { tool: 'query_loans_debts', result: debts });
      toolCalls.push({ tool: 'query_loans_debts', args: {}, result: debts });

      text = `You have lent a total of ${debts.total_lent} ETB and borrowed ${debts.total_borrowed} ETB across ${debts.debts.length} active records.`;
    } else if (lower.includes('reimburs')) {
      sendSse('tool_start', { tool: 'query_reimbursements', arguments: {} });
      const reimbs = await financeTools.queryReimbursements(userId, {});
      sendSse('tool_end', { tool: 'query_reimbursements', result: reimbs });
      toolCalls.push({ tool: 'query_reimbursements', args: {}, result: reimbs });

      text = `You have ${reimbs.total_reimbursements_count} linked reimbursement records.`;
    } else if (amount !== null && (lower.includes('afford') || lower.includes('spend') || lower.includes('buy'))) {
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
      sendSse('delta', { text: part, content: part, type: 'token' });
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
