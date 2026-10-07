import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const DEFAULT_CATEGORIES = [
  { id: '018f3a5e-0001-7000-8000-000000000001', name: 'Food & Groceries', icon: 'utensils', colorHex: '#10B981' },
  { id: '018f3a5e-0002-7000-8000-000000000002', name: 'Transport', icon: 'car', colorHex: '#3B82F6' },
  { id: '018f3a5e-0003-7000-8000-000000000003', name: 'Rent & Housing', icon: 'home', colorHex: '#8B5CF6' },
  { id: '018f3a5e-0004-7000-8000-000000000004', name: 'Utilities', icon: 'zap', colorHex: '#F59E0B' },
  { id: '018f3a5e-0005-7000-8000-000000000005', name: 'Airtime & Data', icon: 'phone', colorHex: '#EC4899' },
  { id: '018f3a5e-0006-7000-8000-000000000006', name: 'Health', icon: 'activity', colorHex: '#EF4444' },
  { id: '018f3a5e-0007-7000-8000-000000000007', name: 'Education', icon: 'book', colorHex: '#6366F1' },
  { id: '018f3a5e-0008-7000-8000-000000000008', name: 'Family & Gifts', icon: 'heart', colorHex: '#F43F5E' },
  { id: '018f3a5e-0009-7000-8000-000000000009', name: 'Shopping', icon: 'shopping-bag', colorHex: '#14B8A6' },
  { id: '018f3a5e-0010-7000-8000-000000000010', name: 'Entertainment', icon: 'film', colorHex: '#A855F7' },
  { id: '018f3a5e-0011-7000-8000-000000000011', name: 'Business', icon: 'briefcase', colorHex: '#64748B' },
  { id: '018f3a5e-0012-7000-8000-000000000012', name: 'Fees & Charges', icon: 'percent', colorHex: '#78716C' },
  { id: '018f3a5e-0013-7000-8000-000000000013', name: 'Savings', icon: 'piggy-bank', colorHex: '#2563EB' },
  { id: '018f3a5e-0014-7000-8000-000000000014', name: 'Debt', icon: 'credit-card', colorHex: '#DC2626' },
  { id: '018f3a5e-0015-7000-8000-000000000015', name: 'Other', icon: 'more-horizontal', colorHex: '#94A3B8' },
];

async function main() {
  console.log('🌱 Seeding default system categories...');
  for (const cat of DEFAULT_CATEGORIES) {
    await prisma.category.upsert({
      where: { id: cat.id },
      create: {
        id: cat.id,
        name: cat.name,
        icon: cat.icon,
        colorHex: cat.colorHex,
        isSystem: true,
        changeSeq: 0n,
      },
      update: {
        name: cat.name,
        icon: cat.icon,
        colorHex: cat.colorHex,
      },
    });
  }
  console.log('✔ System categories seeded successfully.');
}

main()
  .catch((e) => {
    console.error('❌ Seeding error:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
