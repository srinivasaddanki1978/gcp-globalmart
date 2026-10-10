import { useEffect, useRef, useState } from 'react';
import { Button } from '../../components/Button';
import { DashboardHeader } from '../shared/dashboard-ui';

interface Turn {
  question: string;
  answer?: string;
  sql?: string | null;
  rows?: Record<string, unknown>[];
  error?: string | null;
}

const EXAMPLES = [
  'What is the total revenue by customer region?',
  'Which vendor has the highest return rate?',
  'How many customers are flagged as fraud risks?',
  'Which month of 2024 had the highest revenue?',
];

/** Ask page: plain-English questions to the GlobalMart data agent (Conversational Analytics API). */
export function AskPage() {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(false);
  const conversationId = useRef<string | undefined>(undefined);
  const end = useRef<HTMLDivElement>(null);

  useEffect(() => end.current?.scrollIntoView({ behavior: 'smooth' }), [turns]);

  async function ask(question: string) {
    if (!question.trim() || busy) return;
    setBusy(true);
    setInput('');
    setTurns((t) => [...t, { question }]);
    try {
      const r = await fetch('/api/ask', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question, conversationId: conversationId.current }),
      });
      const body = await r.json();
      if (!r.ok) throw new Error(body.error ?? `HTTP ${r.status}`);
      conversationId.current = body.conversationId;
      setTurns((t) => [...t.slice(0, -1), { question, answer: body.text, sql: body.sql, rows: body.rows, error: body.error }]);
    } catch (e) {
      setTurns((t) => [...t.slice(0, -1), { question, error: (e as Error).message }]);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-4 w-full max-w-5xl mx-auto">
      <DashboardHeader title="Ask GlobalMart" source="Data agent globalmart-agent (Conversational Analytics API)" />
      <p className="text-sm text-muted-foreground">
        Ask questions in plain English. The agent writes SQL against the Gold and Metrics tables; open “SQL” under an
        answer to check it.
      </p>

      <div className="rounded-lg border min-h-[420px] p-4 space-y-6">
        {turns.length === 0 && (
          <div className="flex flex-wrap gap-2">
            {EXAMPLES.map((q) => (
              <button key={q} onClick={() => ask(q)} className="rounded-full border px-3 py-1 text-sm hover:bg-muted">
                {q}
              </button>
            ))}
          </div>
        )}
        {turns.map((t, i) => (
          <div key={i} className="space-y-2">
            <div className="ml-auto w-fit max-w-[80%] rounded-lg bg-primary px-3 py-2 text-sm text-primary-foreground">
              {t.question}
            </div>
            {t.answer === undefined && !t.error ? (
              <div className="text-sm text-muted-foreground animate-pulse">Thinking…</div>
            ) : (
              <div className="max-w-[90%] space-y-2 text-sm">
                {t.answer && <div className="whitespace-pre-wrap">{t.answer}</div>}
                {t.error && <div className="text-destructive">Error: {t.error}</div>}
                {t.rows && t.rows.length > 0 && <ResultTable rows={t.rows} />}
                {t.sql && (
                  <details>
                    <summary className="cursor-pointer text-muted-foreground">SQL</summary>
                    <pre className="mt-1 overflow-x-auto rounded bg-muted p-3 text-xs">{t.sql}</pre>
                  </details>
                )}
              </div>
            )}
          </div>
        ))}
        <div ref={end} />
      </div>

      <form
        className="flex gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          ask(input);
        }}
      >
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Ask about revenue, returns, vendors, products…"
          className="h-10 flex-1 rounded-md border bg-background px-3 text-sm"
          maxLength={1000}
        />
        <Button type="submit" disabled={busy || !input.trim()}>
          Ask
        </Button>
      </form>
    </div>
  );
}

function ResultTable({ rows }: { rows: Record<string, unknown>[] }) {
  const cols = Object.keys(rows[0]);
  return (
    <div className="overflow-x-auto rounded border">
      <table className="w-full text-xs">
        <thead className="bg-muted">
          <tr>
            {cols.map((c) => (
              <th key={c} className="px-2 py-1 text-left font-medium">
                {c}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.slice(0, 20).map((r, i) => (
            <tr key={i} className="border-t">
              {cols.map((c) => (
                <td key={c} className="px-2 py-1">
                  {typeof r[c] === 'number' ? (r[c] as number).toLocaleString('en-US') : String(r[c] ?? '')}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      {rows.length > 20 && <div className="px-2 py-1 text-xs text-muted-foreground">Showing 20 of {rows.length} rows</div>}
    </div>
  );
}
