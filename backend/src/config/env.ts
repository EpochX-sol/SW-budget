import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().default(3000),
  HOST: z.string().default('0.0.0.0'),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  JWT_EXPIRES_IN: z.coerce.number().default(900),
  TEMPLATE_SIGNING_PRIVATE_KEY: z.string().optional(),
  TEMPLATE_SIGNING_PUBLIC_KEY: z.string().optional(),
  LLM_PROVIDER: z.string().default('openrouter'),
  GEMINI_API_KEY: z.string().optional(),
  OPENROUTER_API_KEY: z.string().optional(),
  OPENROUTER_BASE_URL: z.string().default('https://openrouter.ai/api/v1'),
  OPENROUTER_MODEL: z.string().default('nvidia/nemotron-3.5-lightning:free'),
});

export const env: z.infer<typeof envSchema> = (() => {
  try {
    return envSchema.parse(process.env);
  } catch (err: any) {
    console.error('❌ Invalid environment variables:', err);
    process.exit(1);
  }
})();
