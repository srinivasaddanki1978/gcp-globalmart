import { createBrowserRouter, Link, NavLink, Outlet, RouterProvider } from 'react-router';
import { useEffect, useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from './lib/ui';
import { AnalyticsPage } from './pages/analytics/AnalyticsPage';
import { AskPage } from './pages/ask/AskPage';
import { CustomersPage } from './pages/customers/CustomersPage';
import { FraudPage } from './pages/fraud/FraudPage';
import { InsightsPage } from './pages/insights/InsightsPage';
import { OperationsPage } from './pages/operations/OperationsPage';
import { ProductsPage } from './pages/products/ProductsPage';
import { SalesPage } from './pages/sales/SalesPage';
import { TrendsPage } from './pages/trends/TrendsPage';

const SECTIONS = [
  { to: '/trends', nav: 'Trends', title: 'Trends 2016 – 2026', text: 'Ten years of revenue, profit and orders, overall and by region.' },
  { to: '/analytics', nav: 'Revenue', title: 'Revenue', text: 'Revenue audit for a single year: totals, regions and months.' },
  { to: '/sales', nav: 'Sales', title: 'Sales', text: 'Brands, segments, ship modes and payment methods.' },
  { to: '/products', nav: 'Products', title: 'Products', text: 'Catalogue breadth vs revenue, top sellers, slow movers.' },
  { to: '/customers', nav: 'Customers', title: 'Customers', text: 'Deduplicated customer base by region and segment.' },
  { to: '/operations', nav: 'Operations', title: 'Operations', text: 'Vendor return rates and inventory tied up in slow movers.' },
  { to: '/fraud', nav: 'Fraud', title: 'Returns Fraud', text: 'Customers flagged for review, with AI investigation briefs.' },
  { to: '/insights', nav: 'AI Insights', title: 'AI Insights', text: 'Gemini executive summaries and data-quality explanations.' },
  { to: '/ask', nav: 'Ask', title: 'Ask GlobalMart', text: 'Ask questions about the data in plain English.' },
];

const linkClass = ({ isActive }: { isActive: boolean }) =>
  `px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
    isActive ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-muted hover:text-foreground'
  }`;

function Layout() {
  const [email, setEmail] = useState<string | null>(null);
  useEffect(() => {
    fetch('/api/me')
      .then((r) => r.json())
      .then((b) => setEmail(b.email))
      .catch(() => undefined);
  }, []);
  return (
    <div className="min-h-screen bg-background flex flex-col">
      <header className="border-b px-4 md:px-6 py-3 flex items-center gap-4 flex-wrap">
        <Link to="/" className="text-lg font-semibold whitespace-nowrap">
          GlobalMart
        </Link>
        <nav className="flex flex-wrap gap-1">
          <NavLink to="/" end className={linkClass}>
            Home
          </NavLink>
          {SECTIONS.map((s) => (
            <NavLink key={s.to} to={s.to} className={linkClass}>
              {s.nav}
            </NavLink>
          ))}
        </nav>
        {email && <span className="ml-auto text-xs text-muted-foreground">{email}</span>}
      </header>
      <main className="flex-1 p-4 md:p-6">
        <Outlet />
      </main>
    </div>
  );
}

function HomePage() {
  return (
    <div className="max-w-6xl mx-auto space-y-6 mt-4">
      <div>
        <h2 className="text-3xl font-bold mb-2">GlobalMart Data Intelligence</h2>
        <p className="text-muted-foreground">
          Six regional retail systems unified on Google Cloud: Bronze → Silver → Gold → Metrics in BigQuery with dbt, plus
          Gemini. Data covers Oct 2016 – Sep 2026 (from Sep 2018 synthetic). Source: <code>gold</code> dataset.
        </p>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {SECTIONS.map((s) => (
          <Link key={s.to} to={s.to} className="group">
            <Card className="shadow-lg h-full transition-colors group-hover:border-primary">
              <CardHeader>
                <CardTitle>{s.title}</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-sm text-muted-foreground">{s.text}</p>
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>
    </div>
  );
}

const router = createBrowserRouter([
  {
    element: <Layout />,
    children: [
      { path: '/', element: <HomePage /> },
      { path: '/trends', element: <TrendsPage /> },
      { path: '/analytics', element: <AnalyticsPage /> },
      { path: '/sales', element: <SalesPage /> },
      { path: '/products', element: <ProductsPage /> },
      { path: '/customers', element: <CustomersPage /> },
      { path: '/operations', element: <OperationsPage /> },
      { path: '/fraud', element: <FraudPage /> },
      { path: '/insights', element: <InsightsPage /> },
      { path: '/ask', element: <AskPage /> },
    ],
  },
]);

export default function App() {
  return <RouterProvider router={router} />;
}
