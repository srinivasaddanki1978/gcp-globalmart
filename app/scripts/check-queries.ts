// CI contract check: dry-run every app query against BigQuery. A renamed or retyped
// Gold column makes the dry run fail, so the build fails before the app breaks.
// Together with dbt contracts (which stop Gold drifting), this protects both sides.
import path from 'node:path';
import { BigQuery } from '@google-cloud/bigquery';
import { loadQueries, queryOptions, type ParamType } from '../server/queries.js';

const SAMPLE: Record<ParamType, unknown> = { INT64: 1, FLOAT64: 1.5, STRING: 'x', BOOL: true };
const project = process.env.GCP_PROJECT ?? 'globalmart-gcp-lab';
const bq = new BigQuery({ projectId: project });
const defs = loadQueries(path.resolve(import.meta.dirname, '..', 'queries'));

let failed = 0;
for (const def of defs.values()) {
  const params = Object.fromEntries(Object.entries(def.params).map(([k, t]) => [k, SAMPLE[t]]));
  try {
    const [job] = await bq.createQueryJob({ ...queryOptions(def, params, 'us-central1'), dryRun: true });
    const mb = Number(job.metadata.statistics.totalBytesProcessed) / 1e6;
    console.log(`OK    ${def.key.padEnd(28)} ${mb.toFixed(1)} MB`);
  } catch (e) {
    failed++;
    console.log(`FAIL  ${def.key.padEnd(28)} ${(e as Error).message.split('\n')[0]}`);
  }
}
console.log(`\n${defs.size - failed}/${defs.size} queries valid`);
process.exit(failed ? 1 : 0);
