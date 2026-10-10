// Minimal shadcn/ui-style components with the same names and props the pages use
// (originally from @databricks/appkit-ui). Tailwind only, no runtime UI library.
import { Children, isValidElement, type ReactElement, type ReactNode } from 'react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export const cn = (...v: ClassValue[]) => twMerge(clsx(v));

type Div = { className?: string; children?: ReactNode };

export const Card = ({ className, children }: Div) => (
  <div className={cn('flex flex-col rounded-xl border bg-card text-card-foreground', className)}>{children}</div>
);
export const CardHeader = ({ className, children }: Div) => <div className={cn('p-5 pb-2', className)}>{children}</div>;
export const CardTitle = ({ className, children }: Div) => (
  <h3 className={cn('font-semibold leading-none tracking-tight', className)}>{children}</h3>
);
export const CardContent = ({ className, children }: Div) => (
  <div className={cn('flex-1 min-w-0 p-5 pt-2', className)}>{children}</div>
);
export const Skeleton = ({ className }: { className?: string }) => (
  <div className={cn('animate-pulse rounded-md bg-muted', className)} />
);
export const Label = ({ htmlFor, children }: { htmlFor?: string; children: ReactNode }) => (
  <label htmlFor={htmlFor} className="text-sm font-medium">
    {children}
  </label>
);

const BADGE = {
  default: 'bg-primary text-primary-foreground',
  secondary: 'bg-muted text-foreground',
  destructive: 'bg-destructive text-white',
  outline: 'border text-foreground',
};
export const Badge = ({ variant = 'default', children }: { variant?: keyof typeof BADGE; children: ReactNode }) => (
  <span className={cn('inline-flex items-center rounded-md px-2 py-0.5 text-xs font-semibold', BADGE[variant])}>
    {children}
  </span>
);

// Select: Radix-style API (Select > SelectTrigger/SelectValue + SelectContent > SelectItem)
// rendered as one accessible native <select>.
type ItemProps = { value: string; children: ReactNode };
export const SelectItem = (_: ItemProps) => null;
export const SelectContent = (_: { children: ReactNode }) => null;
export const SelectTrigger = (_: { id?: string; className?: string; children?: ReactNode }) => null;
export const SelectValue = (_: { placeholder?: string }) => null;

function collect(children: ReactNode, out: { items: ItemProps[]; id?: string }) {
  Children.forEach(children, (child) => {
    if (!isValidElement(child)) return;
    const el = child as ReactElement<{ children?: ReactNode; id?: string } & ItemProps>;
    if (el.type === SelectItem) out.items.push(el.props);
    else if (el.type === SelectTrigger) out.id = el.props.id;
    else collect(el.props.children, out);
  });
}

export function Select({
  value,
  onValueChange,
  children,
}: {
  value: string;
  onValueChange: (v: string) => void;
  children: ReactNode;
}) {
  const found: { items: ItemProps[]; id?: string } = { items: [] };
  collect(children, found);
  return (
    <select
      id={found.id}
      value={value}
      onChange={(e) => onValueChange(e.target.value)}
      className="h-9 w-full rounded-md border bg-background px-3 text-sm"
    >
      {found.items.map((i) => (
        <option key={i.value} value={i.value}>
          {i.children}
        </option>
      ))}
    </select>
  );
}

// Accordion: rendered with <details>/<summary>.
export const Accordion = ({ className, children }: Div & { type?: string; collapsible?: boolean }) => (
  <div className={cn('divide-y', className)}>{children}</div>
);
export const AccordionItem = ({ children }: { value: string; children: ReactNode }) => (
  <details className="group py-2">{children}</details>
);
export const AccordionTrigger = ({ children }: { children: ReactNode }) => (
  <summary className="cursor-pointer list-none py-2 font-medium flex justify-between">
    {children}
    <span className="text-muted-foreground group-open:rotate-180 transition-transform">⌄</span>
  </summary>
);
export const AccordionContent = ({ className, children }: Div) => (
  <div className={cn('pb-2 text-sm text-muted-foreground', className)}>{children}</div>
);
