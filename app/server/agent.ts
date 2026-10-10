// Ask page backend: the GlobalMart data agent on the Conversational Analytics API (v1).
// One API conversation per browser conversation, so follow-up questions keep context.
// Calls run as the app's credentials (sa-app on Cloud Run): the agent queries BigQuery
// with sa-app's read-only access to gold and metrics.
import { randomUUID } from 'node:crypto';
import { GoogleAuth } from 'google-auth-library';

const API = 'https://geminidataanalytics.googleapis.com/v1';

export interface AskResult {
  conversationId: string;
  text: string;
  sql: string | null;
  rows: Record<string, unknown>[];
  error: string | null;
}

interface SystemMessage {
  text?: { parts?: string[]; textType?: string };
  data?: { generatedSql?: string; result?: { data?: Record<string, unknown>[] } };
  error?: { text?: string; message?: string };
}

export class DataAgent {
  private auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
  private parent: string;
  private agentName: string;

  constructor(
    private project: string,
    agentId: string,
  ) {
    this.parent = `projects/${project}/locations/global`;
    this.agentName = `${this.parent}/dataAgents/${agentId}`;
  }

  private async call(method: string, url: string, body?: unknown): Promise<unknown> {
    const client = await this.auth.getClient();
    const res = await client.request({
      url,
      method: method as 'GET' | 'POST',
      data: body,
      headers: { 'x-goog-user-project': this.project },
      timeout: 120_000,
    });
    return res.data;
  }

  async ask(question: string, conversationId?: string): Promise<AskResult> {
    const id = conversationId && /^[a-z0-9-]{8,64}$/.test(conversationId) ? conversationId : `app-${randomUUID()}`;
    const conversation = `${this.parent}/conversations/${id}`;
    if (!conversationId) {
      await this.call('POST', `${API}/${this.parent}/conversations?conversationId=${id}`, {
        agents: [this.agentName],
      });
    }
    const messages = (await this.call('POST', `${API}/${this.parent}:chat`, {
      messages: [{ userMessage: { text: question } }],
      conversationReference: {
        conversation,
        dataAgentContext: { dataAgent: this.agentName, contextVersion: 'PUBLISHED' },
      },
    })) as { systemMessage?: SystemMessage }[];

    const result: AskResult = { conversationId: id, text: '', sql: null, rows: [], error: null };
    const final: string[] = [];
    for (const m of Array.isArray(messages) ? messages : [messages]) {
      const sm = m.systemMessage ?? {};
      if (sm.text?.textType === 'FINAL_RESPONSE') final.push(...(sm.text.parts ?? []));
      if (sm.data?.generatedSql) result.sql = sm.data.generatedSql;
      if (sm.data?.result?.data?.length) result.rows = sm.data.result.data;
      if (sm.error) result.error = sm.error.text ?? sm.error.message ?? 'agent error';
    }
    result.text = final.join('\n\n').trim();
    return result;
  }
}
