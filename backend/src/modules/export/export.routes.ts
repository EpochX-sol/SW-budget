import { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { exportService } from './export.service.js';

const backupSchema = z.object({
  password: z.string().min(8, 'Password must be at least 8 characters'),
});

const restoreSchema = z.object({
  password: z.string().min(8),
  backup_data_base64: z.string().min(10, 'Backup data must be provided as base64'),
});

export const exportRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.addHook('onRequest', fastify.authenticate);

  // 1. Initiate async export job
  fastify.post('/v1/export/jobs', async (request, reply) => {
    const jobId = `export_${Date.now()}`;
    return reply.status(202).send({
      job_id: jobId,
      status: 'completed',
      poll_url: `/v1/export/jobs/${jobId}`,
      download_url: `/v1/export/jobs/${jobId}/download`,
    });
  });

  // 2. Poll export job status
  fastify.get('/v1/export/jobs/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    return reply.status(200).send({
      job_id: id,
      status: 'completed',
      download_url: `/v1/export/jobs/${id}/download`,
    });
  });

  // 3. Download Excel Workbook
  fastify.get('/v1/export/jobs/:id/download', async (request, reply) => {
    const buffer = await exportService.generateExcelWorkbook(request.user.id);
    reply.header('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    reply.header('Content-Disposition', 'attachment; filename="sw_budget_export.xlsx"');
    return reply.status(200).send(buffer);
  });

  // 4. Generate AES-256-GCM Encrypted Backup
  fastify.post('/v1/backup', async (request, reply) => {
    const parse = backupSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({
        type: 'about:blank',
        title: 'Validation Error',
        status: 400,
        detail: parse.error.errors.map((e) => e.message).join(', '),
      });
    }

    const backupBuffer = await exportService.createEncryptedBackup(request.user.id, parse.data.password);
    reply.header('Content-Type', 'application/octet-stream');
    reply.header('Content-Disposition', 'attachment; filename="backup.swbackup"');
    return reply.status(200).send(backupBuffer);
  });

  // 5. Restore from Encrypted Backup
  fastify.post('/v1/backup/restore', async (request, reply) => {
    const parse = restoreSchema.safeParse(request.body);
    if (!parse.success) {
      return reply.status(400).send({
        type: 'about:blank',
        title: 'Validation Error',
        status: 400,
        detail: parse.error.errors.map((e) => e.message).join(', '),
      });
    }

    const buffer = Buffer.from(parse.data.backup_data_base64, 'base64');
    const result = await exportService.restoreEncryptedBackup(request.user.id, buffer, parse.data.password);
    return reply.status(200).send(result);
  });
};
