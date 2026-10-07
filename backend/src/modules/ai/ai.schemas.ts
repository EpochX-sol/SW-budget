import { z } from 'zod';

export const createThreadSchema = z.object({
  title: z.string().min(1).max(100).default('New Conversation'),
});

export const sendMessageSchema = z.object({
  content: z.string().min(1, 'Message cannot be empty').max(4000, 'Message exceeds 4000 character limit'),
});

export const decideProposalSchema = z.object({
  decision: z.enum(['accepted', 'rejected']),
});

export const addMemorySchema = z.object({
  kind: z.enum(['goal', 'habit', 'preference', 'fact', 'decision']),
  content: z.string().min(1).max(1000),
  importance: z.number().int().min(1).max(5).default(3),
  pinned: z.boolean().default(false),
});

export type CreateThreadInput = z.infer<typeof createThreadSchema>;
export type SendMessageInput = z.infer<typeof sendMessageSchema>;
export type DecideProposalInput = z.infer<typeof decideProposalSchema>;
export type AddMemoryInput = z.infer<typeof addMemorySchema>;
