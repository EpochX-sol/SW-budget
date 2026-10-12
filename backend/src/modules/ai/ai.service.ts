import crypto from 'node:crypto';
import { FastifyReply } from 'fastify';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { prisma } from '../../db/prisma.js';
import { env } from '../../config/env.js';
import { financeTools, GEMINI_TOOL_DECLARATIONS, OPENAI_TOOL_DECLARATIONS } from './tools/finance-tools.js';
import { aiMemoryService } from './ai-memory.service.js';
import { toDeterministicUuid } from '../sync/sync.repository.js';

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

    // 2. Normalize and Verify or Auto-Create Thread
    const normalizedThreadId = toDeterministicUuid(threadId);
    let thread = await prisma.aiThread.findFirst({
      where: { id: normalizedThreadId, userId },
    });
    if (!thread) {
      thread = await prisma.aiThread.create({
        data: {
          id: normalizedThreadId,
          userId,
          title: 'Financial Coach',
        },
      });
    }

    // 3. Save User Message
    const userMsg = await prisma.aiMessage.create({
      data: {
        threadId: normalizedThreadId,
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
            where: { threadId: normalizedThreadId, id: { not: userMsg.id } },
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
          let turn = 0;
          const maxTurns = 3;

          while (turn < maxTurns) {
            turn++;
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 35000);

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

              // Continue next turn to allow multi-step tool calls or synthesis
              continue;
            } else if (choiceMsg?.content && choiceMsg.content.trim()) {
              assistantText = choiceMsg.content;
              const parts = assistantText.match(/.{1,60}(\s|$)/g) || [assistantText];
              for (const part of parts) {
                sendSse('delta', { text: part, content: part, type: 'token' });
              }
              tokensUsed = completion.usage?.total_tokens || 350;
              break;
            } else {
              break;
            }
          }

          tokensUsed = Math.max(tokensUsed, 350 + toolCallsExecuted.length * 80);

          if (!assistantText || !assistantText.trim()) {
            console.warn('OpenRouter finished without final text. Synthesizing from tool calls...');
            assistantText = this.synthesizeToolResults(userContent, toolCallsExecuted);
            const parts = assistantText.match(/.{1,60}(\s|$)/g) || [assistantText];
            for (const part of parts) {
              sendSse('delta', { text: part, content: part, type: 'token' });
            }
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
          threadId: normalizedThreadId,
          role: 'assistant',
          content: assistantText,
          toolCalls: toolCallsExecuted.length > 0 ? toolCallsExecuted : undefined,
          tokensUsed,
        },
      });

      // Update thread timestamp
      await prisma.aiThread.update({
        where: { id: normalizedThreadId },
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
    const now = new Date();
    const dateOptions: Intl.DateTimeFormatOptions = {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      timeZone: 'Africa/Addis_Ababa',
    };
    const timeOptions: Intl.DateTimeFormatOptions = {
      hour: '2-digit',
      minute: '2-digit',
      hour12: true,
      timeZone: 'Africa/Addis_Ababa',
    };
    const dateStr = now.toLocaleDateString('en-US', dateOptions);
    const timeStr = now.toLocaleTimeString('en-US', timeOptions);
    const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const currentDay = now.getDate();
    const daysRemaining = Math.max(0, daysInMonth - currentDay);
    const monthName = now.toLocaleDateString('en-US', { month: 'long', timeZone: 'Africa/Addis_Ababa' });

    const memoryContext =
      memories.length > 0
        ? `\n\n### EPISODIC USER MEMORY (Personal Financial Facts)\n${memories.map((m) => `- [${m.kind.toUpperCase()}] ${m.content}`).join('\n')}\nUse these personal facts to customize advice naturally without explicitly announcing "according to your memory".`
        : '';

    return `### REAL-TIME TEMPORAL ANCHOR
- Current Date: ${dateStr}
- Local Time: ${timeStr} (East Africa Time, UTC+3)
- Month Progress: Day ${currentDay} of ${daysInMonth} (${daysRemaining} days remaining in ${monthName})
Use this temporal anchor to answer questions about "today", "yesterday", "this week", "this weekend", or "end of the month" with 100% precision without needing to ask the user what date it is.

### ROLE & MISSION: THE ELITE CFO & FINANCIAL COACH
You are the SW-Budget AI Financial Coach — an empathetic, disciplined, elite-level personal finance strategist and Chief Financial Officer (CFO) for everyday life, specifically tailored for users in Ethiopia.
Your core mission is to empower the user to build wealth, maintain clear visibility over every Birr, stay disciplined under inflationary pressure, and hit their savings goals with confidence.

### THE CARDINAL LAW: "NUMBERS FROM CODE, WORDS FROM AI"
1. NEVER compute sums, balances, forecasts, or monthly totals in your head. Large Language Models hallucinate arithmetic. You MUST obtain ALL figures from tool calls.
2. Whenever the user asks about money, transactions, merchants, balances, limits, debts, or affordability, you MUST invoke the appropriate tool(s).
3. If the user asks a compound question (e.g. "What is my balance and how much have I spent on Ride taxis this month?"), invoke ALL relevant tools across the turns.
4. Once the tools return deterministic JSON data, translate the numbers into a clear, structured executive briefing.
5. Currency: Always format numbers as ETB (Ethiopian Birr) with thousands separators (e.g., 2,500 ETB, 45,000 ETB).

### THE 8-ARCHETYPE FINANCIAL INTENT TAXONOMY (TOOL ROUTING MATRIX)
Match the user's intent to one or more of these 8 archetypes and invoke the corresponding tool immediately:

1. ARCHETYPE: STATUS & LIQUIDITY
   - User Intent: "What is my balance?", "How much money do I have?", "Check my bank balance", "How much is in CBE / Telebirr / Abyssinia / Cash?".
   - Primary Tool: "get_account_balances"
   - Execution: NEVER ask what time period the user wants. Call "get_account_balances" immediately.

2. ARCHETYPE: HISTORICAL AUDIT & RECEIPTS
   - User Intent: "What was my last expense?", "Find transactions over 500 ETB", "Show my grocery transactions", "How much did I spend at Kaldi's / on Feres / on Ride?".
   - Primary Tools:
     - For specific merchants: "search_merchant_spending" (merchant_name: string, period?: string)
     - For granular transaction filtering: "query_transactions" (query?, period?, min_amount?, max_amount?, category_name?, type?, limit?)

3. ARCHETYPE: MACRO VELOCITY & BREAKDOWN
   - User Intent: "How is my spending looking this month?", "Where did all my money go?", "Show my top spending categories", "What were my biggest expenses?".
   - Primary Tools:
     - Overall total & net savings: "get_spending_summary" (period: 'today' | 'this_week' | 'this_month' | 'last_month')
     - Largest individual expenses: "get_top_expenses" (period?: string, limit?: number)
     - Category distribution & percentages: "get_category_breakdown" (period?: string)

4. ARCHETYPE: PURCHASING SIMULATION & AFFORDABILITY
   - User Intent: "Can I afford to buy X for 3,500 ETB?", "Should I buy this?", "If I spend 800 ETB today, will I stay on budget?".
   - Primary Tools:
     - Immediate purchase simulation: "simulate_scenario" (amount: number, category_id?: string)
     - Multi-day plan rate simulation: "simulate_plan_spending" (proposed_spend_amount: number)
   - Rule: Always calculate remaining headroom, new safe daily allowance for the remaining ${daysRemaining} days, and deficit pace.

5. ARCHETYPE: COMMITMENTS, DEBTS & COUNTERPARTIES
   - User Intent: "Who owes me money?", "What debts do I owe?", "What subscriptions or recurring bills do I have?", "Did my friend reimburse me?".
   - Primary Tools:
     - Peer loans & borrowed debt: "query_loans_debts" (status?: 'active' | 'settled' | 'all', person_name?: string)
     - Recurring bills / subscriptions: "detect_recurring_bills"
     - Linked split-bill reimbursements: "query_reimbursements"

6. ARCHETYPE: SAVINGS & WEALTH ACCUMULATION
   - User Intent: "How are my savings goals doing?", "How much have I saved toward my emergency fund / car / travel?", "How far am I from my target?".
   - Primary Tool: "query_saving_goals"
   - Rule: Report current saved amount, target, remaining balance, and completion percentage.

7. ARCHETYPE: ADAPTIVE BUDGET PACING & LIMITS
   - User Intent: "What is my daily allowance today?", "How much can I spend tomorrow?", "Am I over my budget limits?", "What's my streak?".
   - Primary Tools:
     - Live dynamic daily/weekly allowances & rollover: "get_active_plan_snapshot"
     - Monthly category & overall limits: "get_budget_status"

8. ARCHETYPE: FINANCIAL EDUCATION & WISDOM
   - User Intent: "How should I budget in Addis Ababa?", "How does an Equb work?", "What is the 50/30/20 rule during inflation?".
   - Primary Action: Provide grounded, insightful financial literacy without mental math or hallucinated user records.

### THE 3-STEP CFO RESPONSE PROTOCOL (MOBILE-FIRST SCANNABLE LAYOUT)
Format EVERY response following this crisp 3-step executive structure:
1. **The Bottom Line (Headline)**:
   - State the direct, definitive answer in bold in the very first sentence with exact figures in ETB.
   - Example: "You currently have **24,500 ETB** in total liquid funds across your CBE and Telebirr accounts."
2. **The Context Breakdown (Bullets)**:
   - Provide 2 to 4 short, scannable bullet points detailing the breakdown, categories, or recent line items.
   - Example:
     - **CBE**: 18,000 ETB
     - **Telebirr**: 6,500 ETB
     - **This Month Spent**: 4,200 ETB (${daysRemaining} days remaining in ${monthName})
3. **The Proactive Next Step (Actionable Coaching)**:
   - Close with exactly 1 concrete recommendation, practical trade-off, or encouraging follow-up.
   - Example: "You have ${daysRemaining} days left in ${monthName}. To maintain your savings targets, aim to keep discretionary daily spend under 450 ETB/day."

### ETHIOPIAN SOCIO-ECONOMIC REALITIES & LOCAL FINANCIAL CONTEXT
- **Payment Ecosystem**: Deeply understand CBE (Commercial Bank of Ethiopia), CBE Birr, Telebirr, Awash Bank, Bank of Abyssinia, Dashen Bank (Amole), and physical Cash (ኪስ / በእጅ ያለ).
- **Daily Micro-Spending**: Recognize essential daily routines: Buna (coffee ceremonies / macchiato), Bajaj fares, minibus taxi hops, Ride / Feres / ZayRide / PickPick trips, lunch/dinner (ምሳ, እራት, እንጀራ).
- **Traditional & Informal Finance**:
  - **Equb (እቁብ)**: Rotating savings groups. Treat Equb contributions as disciplined savings/commitments and Equb payouts as planned lump sums.
  - **Iddir (እድር)**: Traditional mutual aid / community insurance.
  - **Family Support / Remittances**: Informal remittances and family allowances.
- **Inflation & Purchasing Power**: Treat cash-flow preservation with utmost respect. Focus on essential liquidity, maintaining a margin of safety, and avoiding impulse outlays.

### BILINGUAL & MULTI-LINGUAL CODE-SWITCHING
- **English**: If the user writes in English, reply in crisp, professional English.
- **Amharic (ግዕዝ)**: If the user writes in Amharic script (ለምሳሌ፡ "የዚህ ወር ወጪዬ ስንት ነው?"), reply fluently and respectfully in Amharic while retaining precise numbers and ETB currency labels (ለምሳሌ፡ **3,450 ብር**).
- **Amglish (Latinized Amharic)**: If the user writes in phonetic Amharic (e.g. "Balance-e sint new?", "Kaldis lay sint awetahu?"), understand the question perfectly and reply either in clean Amharic script or natural bilingual style as preferred by context.

### COMMUNICATION & TONE PRINCIPLES
1. **Empathetic & Non-Judgmental**: Never shame or scold the user for overspending. Acknowledge deficits with calm, proactive steps to recover.
2. **Concise & Scannable**: Mobile screens have limited space. Avoid giant walls of continuous prose. Use bullet points and bold figures.
3. **Graceful Empty-Ledger Guidance**: If a tool returns 0 accounts or 0 transactions, never leave the user hanging. Explain warmly: "I don't see any recorded transactions yet. Once you connect SMS parsing or add your CBE/Telebirr accounts, I will track every Birr for you!"
4. **Safety & Security**: Never ask for, handle, or store PINs, OTPs, or passwords.${memoryContext}`;
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
    if (toolName === 'query_transactions') {
      return financeTools.queryTransactions(userId, args);
    }
    if (toolName === 'search_merchant_spending') {
      return financeTools.searchMerchantSpending(userId, args);
    }
    if (toolName === 'get_top_expenses') {
      return financeTools.getTopExpenses(userId, args);
    }
    if (toolName === 'get_category_breakdown') {
      return financeTools.getCategoryBreakdown(userId, args);
    }
    if (toolName === 'detect_recurring_bills') {
      return financeTools.detectRecurringBills(userId);
    }
    if (toolName === 'query_saving_goals') {
      return financeTools.querySavingGoals(userId);
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
      } else if (tool === 'query_transactions') {
        if (result.transactions && result.transactions.length > 0) {
          const lines = result.transactions.slice(0, 7).map(
            (t: any) => `- **${t.date}**: ${t.merchant} (${t.category}) — **${Number(t.amount).toLocaleString()} ETB** [${t.type}]`
          );
          messages.push(`Found **${result.total_matches}** transactions (Total: **${Number(result.total_sum).toLocaleString()} ETB**):\n\n` + lines.join('\n'));
        } else {
          messages.push(`No transactions matched your search criteria.`);
        }
      } else if (tool === 'search_merchant_spending') {
        messages.push(`You have **${result.transaction_count}** transactions with **${result.merchant_query}** totaling **${Number(result.total_spent).toLocaleString()} ETB** (Average: **${Number(result.average_spend).toLocaleString()} ETB**).`);
      } else if (tool === 'get_top_expenses') {
        if (result.top_expenses && result.top_expenses.length > 0) {
          const lines = result.top_expenses.map(
            (e: any, i: number) => `${i + 1}. **${e.merchant}** (${e.category}): **${Number(e.amount).toLocaleString()} ETB** on ${e.date}`
          );
          messages.push(`Your top expenses for **${result.period}** are:\n\n` + lines.join('\n'));
        } else {
          messages.push(`No expense records found for ${result.period}.`);
        }
      } else if (tool === 'get_category_breakdown') {
        if (result.categories && result.categories.length > 0) {
          const lines = result.categories.map(
            (c: any) => `- **${c.category}**: ${Number(c.amount).toLocaleString()} ETB (${c.percentage}%)`
          );
          messages.push(`Category breakdown for **${result.period}** (Total: **${Number(result.total_expense).toLocaleString()} ETB**):\n\n` + lines.join('\n'));
        } else {
          messages.push(`No category expense data available.`);
        }
      } else if (tool === 'detect_recurring_bills') {
        if (result.has_recurring) {
          const lines = result.recurring_bills.map(
            (r: any) => `- **${r.merchant}** (${r.category}): ~**${Number(r.average_amount).toLocaleString()} ETB**/month (last paid ${r.last_charged})`
          );
          messages.push(`Identified recurring commitments (~**${Number(result.estimated_monthly_commitment).toLocaleString()} ETB**/month):\n\n` + lines.join('\n'));
        } else {
          messages.push(`No recurring subscriptions or repeat bills detected in the last 60 days.`);
        }
      } else if (tool === 'query_saving_goals') {
        if (result.saving_goals && result.saving_goals.length > 0) {
          const lines = result.saving_goals.map(
            (g: any) => `- **${g.name}**: ${Number(g.current_amount).toLocaleString()} / ${Number(g.target_amount).toLocaleString()} ETB (${g.percentage_completed}% completed)`
          );
          messages.push(`Your saving goals:\n\n` + lines.join('\n'));
        } else {
          messages.push(`You currently have no saving goals configured.`);
        }
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
    } else if (lower.includes('top') || lower.includes('biggest') || lower.includes('highest') || lower.includes('largest')) {
      sendSse('tool_start', { tool: 'get_top_expenses', arguments: { period: 'this_month' } });
      const res = await financeTools.getTopExpenses(userId, { period: 'this_month' });
      sendSse('tool_end', { tool: 'get_top_expenses', result: res });
      toolCalls.push({ tool: 'get_top_expenses', args: { period: 'this_month' }, result: res });
      text = this.synthesizeToolResults(userContent, [{ tool: 'get_top_expenses', result: res }]);
    } else if (lower.includes('category') || lower.includes('breakdown') || lower.includes('distribution')) {
      sendSse('tool_start', { tool: 'get_category_breakdown', arguments: { period: 'this_month' } });
      const res = await financeTools.getCategoryBreakdown(userId, { period: 'this_month' });
      sendSse('tool_end', { tool: 'get_category_breakdown', result: res });
      toolCalls.push({ tool: 'get_category_breakdown', args: { period: 'this_month' }, result: res });
      text = this.synthesizeToolResults(userContent, [{ tool: 'get_category_breakdown', result: res }]);
    } else if (lower.includes('recurring') || lower.includes('subscription') || lower.includes('bill')) {
      sendSse('tool_start', { tool: 'detect_recurring_bills', arguments: {} });
      const res = await financeTools.detectRecurringBills(userId);
      sendSse('tool_end', { tool: 'detect_recurring_bills', result: res });
      toolCalls.push({ tool: 'detect_recurring_bills', args: {}, result: res });
      text = this.synthesizeToolResults(userContent, [{ tool: 'detect_recurring_bills', result: res }]);
    } else if (lower.includes('goal') || lower.includes('saving')) {
      sendSse('tool_start', { tool: 'query_saving_goals', arguments: {} });
      const res = await financeTools.querySavingGoals(userId);
      sendSse('tool_end', { tool: 'query_saving_goals', result: res });
      toolCalls.push({ tool: 'query_saving_goals', args: {}, result: res });
      text = this.synthesizeToolResults(userContent, [{ tool: 'query_saving_goals', result: res }]);
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
    } else if (lower.includes('transaction') || lower.includes('history') || lower.includes('recent')) {
      sendSse('tool_start', { tool: 'query_transactions', arguments: { limit: 10 } });
      const res = await financeTools.queryTransactions(userId, { limit: 10 });
      sendSse('tool_end', { tool: 'query_transactions', result: res });
      toolCalls.push({ tool: 'query_transactions', args: { limit: 10 }, result: res });
      text = this.synthesizeToolResults(userContent, [{ tool: 'query_transactions', result: res }]);
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
