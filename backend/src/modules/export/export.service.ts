import crypto from 'node:crypto';
import ExcelJS from 'exceljs';
import { prisma } from '../../db/prisma.js';
import { Prisma } from '@prisma/client';

const MAGIC_HEADER = Buffer.from('SWBACKUP1'); // 9 bytes

export class ExportService {
  /**
   * Generates a multi-sheet Excel spreadsheet with UTF-8 encoding supporting Amharic.
   */
  async generateExcelWorkbook(userId: string): Promise<Buffer> {
    const [accounts, categories, transactions, limits] = await Promise.all([
      prisma.account.findMany({ where: { userId, deletedAt: null } }),
      prisma.category.findMany({ where: { OR: [{ isSystem: true }, { userId }], deletedAt: null } }),
      prisma.transaction.findMany({
        where: { userId, deletedAt: null },
        orderBy: { occurredAt: 'desc' },
        take: 2000,
      }),
      prisma.limit.findMany({ where: { userId, deletedAt: null } }),
    ]);

    const catMap = new Map(categories.map((c: { id: any; name: any; }) => [c.id, c.name]));
    const accMap = new Map(accounts.map((a: { id: any; name: any; }) => [a.id, a.name]));

    const workbook = new ExcelJS.Workbook();
    workbook.creator = 'SW-budget System';
    workbook.created = new Date();

    // 1. Transactions Sheet
    const txSheet = workbook.addWorksheet('Transactions');
    txSheet.columns = [
      { header: 'Transaction ID', key: 'id', width: 36 },
      { header: 'Date & Time', key: 'date', width: 22 },
      { header: 'Account', key: 'account', width: 20 },
      { header: 'Category', key: 'category', width: 22 },
      { header: 'Type', key: 'type', width: 12 },
      { header: 'Amount (ETB)', key: 'amount', width: 15 },
      { header: 'Counterparty', key: 'counterparty', width: 25 },
      { header: 'Reference', key: 'reference', width: 18 },
    ];

    for (const t of transactions) {
      txSheet.addRow({
        id: t.id,
        date: t.occurredAt.toISOString(),
        account: accMap.get(t.accountId) || 'Unknown Account',
        category: (t.categoryId && catMap.get(t.categoryId)) || 'Uncategorized',
        type: t.type.toUpperCase(),
        amount: Number(t.amount),
        counterparty: t.counterparty || '',
        reference: t.reference || '',
      });
    }

    // 2. Accounts Sheet
    const accSheet = workbook.addWorksheet('Accounts');
    accSheet.columns = [
      { header: 'Account Name', key: 'name', width: 25 },
      { header: 'Provider', key: 'provider', width: 15 },
      { header: 'Account Mask', key: 'mask', width: 15 },
      { header: 'Balance (ETB)', key: 'balance', width: 18 },
    ];

    for (const a of accounts) {
      accSheet.addRow({
        name: a.name,
        provider: a.provider,
        mask: a.accountMask || '',
        balance: a.lastKnownBalance ? Number(a.lastKnownBalance) : 0,
      });
    }

    // 3. Limits Sheet
    const limSheet = workbook.addWorksheet('Limits');
    limSheet.columns = [
      { header: 'Scope', key: 'scope', width: 15 },
      { header: 'Amount (ETB)', key: 'amount', width: 15 },
      { header: 'Period', key: 'period', width: 12 },
      { header: 'Mode', key: 'mode', width: 10 },
    ];

    for (const l of limits) {
      limSheet.addRow({
        scope: l.scopeType,
        amount: Number(l.amount),
        period: l.periodType,
        mode: l.mode,
      });
    }

    const buffer = await workbook.xlsx.writeBuffer();
    return Buffer.from(buffer);
  }

  /**
   * Creates an encrypted backup payload using AES-256-GCM.
   */
  async createEncryptedBackup(userId: string, password: string): Promise<Buffer> {
    const [user, accounts, categories, transactions, limits] = await Promise.all([
      prisma.user.findUnique({ where: { id: userId } }),
      prisma.account.findMany({ where: { userId } }),
      prisma.category.findMany({ where: { userId } }),
      prisma.transaction.findMany({ where: { userId } }),
      prisma.limit.findMany({ where: { userId } }),
    ]);

    const backupData = {
      version: 1,
      timestamp: new Date().toISOString(),
      user: {
        id: user?.id,
        email: user?.email,
        displayName: user?.displayName,
        currency: user?.currency,
      },
      accounts,
      categories,
      transactions,
      limits,
    };

    const plaintext = Buffer.from(JSON.stringify(backupData), 'utf-8');

    // 16-byte salt, 12-byte IV for AES-256-GCM
    const salt = crypto.randomBytes(16);
    const iv = crypto.randomBytes(12);
    const key = crypto.scryptSync(password, salt, 32);

    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
    const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const tag = cipher.getAuthTag(); // 16 bytes

    // Format: MAGIC (9) + SALT (16) + IV (12) + TAG (16) + CIPHERTEXT (...)
    return Buffer.concat([MAGIC_HEADER, salt, iv, tag, ciphertext]);
  }

  /**
   * Decrypts and restores an encrypted .swbackup payload.
   */
  async restoreEncryptedBackup(userId: string, backupBuffer: Buffer, password: string) {
    if (backupBuffer.length < 9 + 16 + 12 + 16) {
      throw new Error('Invalid backup file: file too short');
    }

    const header = backupBuffer.subarray(0, 9);
    if (!header.equals(MAGIC_HEADER)) {
      throw new Error('Invalid backup file: unrecognized format header');
    }

    let offset = 9;
    const salt = backupBuffer.subarray(offset, offset + 16);
    offset += 16;
    const iv = backupBuffer.subarray(offset, offset + 12);
    offset += 12;
    const tag = backupBuffer.subarray(offset, offset + 16);
    offset += 16;
    const ciphertext = backupBuffer.subarray(offset);

    const key = crypto.scryptSync(password, salt, 32);
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(tag);

    let plaintext: Buffer;
    try {
      plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    } catch {
      const err = new Error('Incorrect backup password or corrupted backup file');
      (err as any).statusCode = 400;
      throw err;
    }

    const data = JSON.parse(plaintext.toString('utf-8'));

    // Transactionally restore categories, accounts, limits, and transactions
    const result = await prisma.$transaction(async (tx: { category: { findUnique: (arg0: { where: { id: any; }; }) => any; upsert: (arg0: { where: { id: any; }; create: { id: any; userId: string; name: any; icon: any; colorHex: any; isSystem: boolean; changeSeq: bigint; }; update: { name: any; icon: any; colorHex: any; }; }) => any; }; account: { findUnique: (arg0: { where: { id: any; }; }) => any; upsert: (arg0: { where: { id: any; }; create: { id: any; userId: string; provider: any; name: any; accountMask: any; lastKnownBalance: any; isSavings: any; changeSeq: bigint; }; update: { name: any; lastKnownBalance: any; isSavings: any; }; }) => any; }; limit: { findUnique: (arg0: { where: { id: any; }; }) => any; upsert: (arg0: { where: { id: any; }; create: { id: any; userId: string; scopeType: any; scopeId: any; periodType: any; amount: any; mode: any; rollover: any; alertThresholds: any; active: any; changeSeq: bigint; }; update: { amount: any; active: any; }; }) => any; }; transaction: { findUnique: (arg0: { where: { id: any; }; }) => any; upsert: (arg0: { where: { id: any; }; create: { id: any; userId: string; accountId: any; categoryId: any; type: any; amount: any; balanceAfter: any; counterparty: any; reference: any; note: any; occurredAt: Date; source: any; dedupeKey: any; needsReview: any; userEditedFields: any; changeSeq: bigint; }; update: { note: any; categoryId: any; }; }) => any; }; }) => {
      // 1. Restore categories
      let catCount = 0;
      if (Array.isArray(data.categories)) {
        for (const cat of data.categories) {
          if (!cat.id || cat.isSystem) continue;
          const existingCat = await tx.category.findUnique({ where: { id: cat.id } });
          if (existingCat && existingCat.userId !== userId) continue; // Prevent cross-tenant tampering

          await tx.category.upsert({
            where: { id: cat.id },
            create: {
              id: cat.id,
              userId,
              name: cat.name,
              icon: cat.icon || 'tag',
              colorHex: cat.colorHex || '#4F46E5',
              isSystem: false,
              changeSeq: BigInt(cat.changeSeq || 1),
            },
            update: {
              name: cat.name,
              icon: cat.icon || 'tag',
              colorHex: cat.colorHex || '#4F46E5',
            },
          });
          catCount++;
        }
      }

      // 2. Restore accounts
      let accCount = 0;
      if (Array.isArray(data.accounts)) {
        for (const acc of data.accounts) {
          if (!acc.id) continue;
          const existingAcc = await tx.account.findUnique({ where: { id: acc.id } });
          if (existingAcc && existingAcc.userId !== userId) continue; // Prevent cross-tenant tampering

          await tx.account.upsert({
            where: { id: acc.id },
            create: {
              id: acc.id,
              userId,
              provider: acc.provider,
              name: acc.name,
              accountMask: acc.accountMask,
              lastKnownBalance: acc.lastKnownBalance != null ? new Prisma.Decimal(acc.lastKnownBalance) : null,
              isSavings: acc.isSavings || false,
              changeSeq: BigInt(acc.changeSeq || 1),
            },
            update: {
              name: acc.name,
              lastKnownBalance: acc.lastKnownBalance != null ? new Prisma.Decimal(acc.lastKnownBalance) : null,
              isSavings: acc.isSavings || false,
            },
          });
          accCount++;
        }
      }

      // 3. Restore limits
      let limCount = 0;
      if (Array.isArray(data.limits)) {
        for (const lim of data.limits) {
          if (!lim.id) continue;
          const existingLim = await tx.limit.findUnique({ where: { id: lim.id } });
          if (existingLim && existingLim.userId !== userId) continue;

          await tx.limit.upsert({
            where: { id: lim.id },
            create: {
              id: lim.id,
              userId,
              scopeType: lim.scopeType || 'overall',
              scopeId: lim.scopeId || null,
              periodType: lim.periodType || 'monthly',
              amount: new Prisma.Decimal(lim.amount || 0),
              mode: lim.mode || 'soft',
              rollover: lim.rollover || false,
              alertThresholds: lim.alertThresholds || [50, 80, 100],
              active: lim.active ?? true,
              changeSeq: BigInt(lim.changeSeq || 1),
            },
            update: {
              amount: new Prisma.Decimal(lim.amount || 0),
              active: lim.active ?? true,
            },
          });
          limCount++;
        }
      }

      // 4. Restore transactions
      let txnCount = 0;
      if (Array.isArray(data.transactions)) {
        for (const t of data.transactions) {
          if (!t.id || !t.accountId) continue;
          const existingTxn = await tx.transaction.findUnique({ where: { id: t.id } });
          if (existingTxn && existingTxn.userId !== userId) continue;

          await tx.transaction.upsert({
            where: { id: t.id },
            create: {
              id: t.id,
              userId,
              accountId: t.accountId,
              categoryId: t.categoryId || null,
              type: t.type || 'expense',
              amount: new Prisma.Decimal(t.amount || 0),
              balanceAfter: t.balanceAfter != null ? new Prisma.Decimal(t.balanceAfter) : null,
              counterparty: t.counterparty || null,
              reference: t.reference || null,
              note: t.note || null,
              occurredAt: new Date(t.occurredAt || new Date()),
              source: t.source || 'backup',
              dedupeKey: t.dedupeKey || `backup_${t.id}`,
              needsReview: t.needsReview || false,
              userEditedFields: t.userEditedFields || [],
              changeSeq: BigInt(t.changeSeq || 1),
            },
            update: {
              note: t.note || null,
              categoryId: t.categoryId || null,
            },
          });
          txnCount++;
        }
      }

      return { accCount, catCount, limCount, txnCount };
    });

    return {
      success: true,
      restored_at: new Date().toISOString(),
      accounts_count: result.accCount,
      categories_count: result.catCount,
      limits_count: result.limCount,
      transactions_count: result.txnCount,
    };
  }
}

export const exportService = new ExportService();
