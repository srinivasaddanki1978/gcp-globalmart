import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express, { type NextFunction, type Request, type Response } from 'express';
import { BigQuery } from '@google-cloud/bigquery';
import { DataAgent } from './agent.js';
import { callerEmail } from './identity.js';
import { QueryError, QueryRunner, loadQueries } from './queries.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), process.env.NODE_ENV === 'production' ? '../..' : '..');
const PROJECT = process.env.GCP_PROJECT ?? 'globalmart-gcp-lab';
const LOCATION = process.env.BQ_LOCATION ?? 'us-central1';
const PORT = Number(process.env.PORT ?? 8080);

const queries = loadQueries(path.join(ROOT, 'queries'));
const runner = new QueryRunner(new BigQuery({ projectId: PROJECT }), queries, LOCATION);
const agent = new DataAgent(PROJECT, process.env.AGENT_ID ?? 'globalmart-agent');

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '16kb' }));

app.get('/api/health', (_req, res) => res.json({ ok: true, queries: queries.size }));

app.get('/api/me', (req, res) => res.json({ email: callerEmail(req), project: PROJECT }));

app.post('/api/query/:key', async (req, res, next) => {
  try {
    res.json({ rows: await runner.run(req.params.key, req.body?.parameters) });
  } catch (e) {
    next(e);
  }
});

app.post('/api/ask', async (req, res, next) => {
  const question = typeof req.body?.question === 'string' ? req.body.question.trim() : '';
  if (!question || question.length > 1000) return next(new QueryError('question must be 1-1000 characters'));
  try {
    console.log(JSON.stringify({ event: 'ask', user: callerEmail(req), question }));
    res.json(await agent.ask(question, req.body?.conversationId));
  } catch (e) {
    next(e);
  }
});

app.use('/api', (_req, res) => res.status(404).json({ error: 'not found' }));

// dbt docs (static site generated in CI), behind the same Cloud Run sign-in.
app.use('/dbt-docs', express.static(path.join(ROOT, 'dbt-docs')));

const clientDist = path.join(ROOT, 'client', 'dist');
app.use(express.static(clientDist, { index: false, maxAge: '1h' }));
app.get(/^\/(?!api\/|dbt-docs).*/, (_req, res) => res.sendFile(path.join(clientDist, 'index.html')));

app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  if (err instanceof QueryError) return res.status(err.status).json({ error: err.message });
  console.error(err);
  res.status(500).json({ error: 'query failed' });
});

app.listen(PORT, () => console.log(`GlobalMart app on :${PORT} (${queries.size} queries, project ${PROJECT})`));
