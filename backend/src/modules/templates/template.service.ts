import * as ed from '@noble/ed25519';
import { env } from '../../config/env.js';

export interface SmsTemplate {
  id: string;
  bank: 'CBE' | 'TELEBIRR' | 'ABYSSINIA';
  version: number;
  match: string;
  type: string;
  fields: {
    amount: string;
    balance?: string;
    reference?: string;
    counterparty?: string;
  };
}

export const OFFICIAL_TEMPLATES: SmsTemplate[] = [
  {
    id: 'cbe_debit_v1',
    bank: 'CBE',
    version: 3,
    match: '(?i)debited|transferred',
    type: 'expense',
    fields: {
      amount: 'ETB\\s?([\\d,]+\\.?\\d*)',
      balance: '(?i)balance(?: is)?\\s*:?\\s*ETB\\s?([\\d,]+\\.?\\d*)',
      reference: '(?i)ref(?:erence)?(?: no)?[:.]?\\s*([A-Z0-9]+)',
      counterparty: '(?i)to\\s+([A-Za-z ]+?)(?:\\s+on|\\.|,)',
    },
  },
  {
    id: 'cbe_credit_v1',
    bank: 'CBE',
    version: 3,
    match: '(?i)credited|received',
    type: 'income',
    fields: {
      amount: 'ETB\\s?([\\d,]+\\.?\\d*)',
      balance: '(?i)balance(?: is)?\\s*:?\\s*ETB\\s?([\\d,]+\\.?\\d*)',
      reference: '(?i)ref(?:erence)?(?: no)?[:.]?\\s*([A-Z0-9]+)',
      counterparty: '(?i)from\\s+([A-Za-z ]+?)(?:\\s+on|\\.|,)',
    },
  },
  {
    id: 'telebirr_payment_v1',
    bank: 'TELEBIRR',
    version: 3,
    match: '(?i)completed.*transaction of ETB',
    type: 'merchant_payment',
    fields: {
      amount: 'ETB\\s?([\\d,]+\\.?\\d*)',
      balance: '(?i)current balance is ETB\\s?([\\d,]+\\.?\\d*)',
      reference: '(?i)transaction ID\\s*:?\\s*([A-Z0-9]+)',
      counterparty: '(?i)to\\s+([A-Za-z0-9 ]+?)(?:\\s+on|\\.)',
    },
  },
  {
    id: 'abyssinia_transfer_v1',
    bank: 'ABYSSINIA',
    version: 2,
    match: '(?i)BoA.*debited',
    type: 'expense',
    fields: {
      amount: 'ETB\\s?([\\d,]+\\.?\\d*)',
      balance: '(?i)available balance is ETB\\s?([\\d,]+\\.?\\d*)',
      reference: '(?i)txn\\s*id\\s*:?\\s*([A-Z0-9]+)',
      counterparty: '(?i)paid to\\s+([A-Za-z ]+?)(?:\\s+on|\\.)',
    },
  },
];

export class TemplateService {
  async getSignedBundle() {
    const bundleVersion = 3;
    const publishedAt = new Date().toISOString();
    const payload = JSON.stringify({
      version: bundleVersion,
      templates: OFFICIAL_TEMPLATES,
    });

    let signature = '';
    if (env.TEMPLATE_SIGNING_PRIVATE_KEY) {
      const privateKeyBytes = Buffer.from(env.TEMPLATE_SIGNING_PRIVATE_KEY, 'hex');
      const messageBytes = Buffer.from(payload, 'utf-8');
      const sigBytes = await ed.signAsync(messageBytes, privateKeyBytes);
      signature = Buffer.from(sigBytes).toString('hex');
    }

    return {
      bundle_version: bundleVersion,
      published_at: publishedAt,
      public_key: env.TEMPLATE_SIGNING_PUBLIC_KEY || '',
      signature,
      templates: OFFICIAL_TEMPLATES,
    };
  }
}

export const templateService = new TemplateService();
