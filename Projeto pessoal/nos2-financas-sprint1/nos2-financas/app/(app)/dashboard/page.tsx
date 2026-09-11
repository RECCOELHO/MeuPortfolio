import { createClient } from '@/lib/supabase/server';

export default async function DashboardPage() {
  const supabase = await createClient();

  const startOfMonth = new Date();
  startOfMonth.setDate(1);
  const startOfMonthStr = startOfMonth.toISOString().slice(0, 10);

  const { data: transactions } = await supabase
    .from('transactions')
    .select('id, description, amount, type, occurred_at, categories(name, icon)')
    .gte('occurred_at', startOfMonthStr)
    .order('occurred_at', { ascending: false });

  const income = transactions
    ?.filter((t) => t.type === 'income')
    .reduce((sum, t) => sum + Number(t.amount), 0) ?? 0;
  const expense = transactions
    ?.filter((t) => t.type === 'expense')
    .reduce((sum, t) => sum + Number(t.amount), 0) ?? 0;
  const balance = income - expense;

  const byCategory = new Map<string, number>();
  transactions
    ?.filter((t) => t.type === 'expense')
    .forEach((t) => {
      const name = t.categories?.name ?? 'Sem categoria';
      byCategory.set(name, (byCategory.get(name) ?? 0) + Number(t.amount));
    });

  return (
    <div className="p-6 max-w-2xl mx-auto space-y-8">
      <h1 className="text-2xl font-semibold">Dashboard</h1>

      <div className="grid grid-cols-3 gap-3">
        <div className="border border-neutral-800 rounded-lg p-4">
          <p className="text-sm text-neutral-500">Receitas do mês</p>
          <p className="text-xl font-semibold text-emerald-400">R$ {income.toFixed(2)}</p>
        </div>
        <div className="border border-neutral-800 rounded-lg p-4">
          <p className="text-sm text-neutral-500">Gastos do mês</p>
          <p className="text-xl font-semibold text-red-400">R$ {expense.toFixed(2)}</p>
        </div>
        <div className="border border-neutral-800 rounded-lg p-4">
          <p className="text-sm text-neutral-500">Saldo</p>
          <p className={`text-xl font-semibold ${balance >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
            R$ {balance.toFixed(2)}
          </p>
        </div>
      </div>

      <div>
        <h2 className="text-lg font-medium mb-3">Gasto por categoria (mês atual)</h2>
        <ul className="space-y-2">
          {[...byCategory.entries()]
            .sort((a, b) => b[1] - a[1])
            .map(([name, total]) => (
              <li key={name} className="flex justify-between border border-neutral-800 rounded-lg px-4 py-2">
                <span>{name}</span>
                <span>R$ {total.toFixed(2)}</span>
              </li>
            ))}
          {byCategory.size === 0 && (
            <p className="text-neutral-500 text-sm">Nenhum gasto registrado este mês ainda.</p>
          )}
        </ul>
      </div>

      <div>
        <h2 className="text-lg font-medium mb-3">Últimas transações</h2>
        <ul className="space-y-2">
          {transactions?.slice(0, 10).map((t) => (
            <li
              key={t.id}
              className="flex justify-between border border-neutral-800 rounded-lg px-4 py-2 text-sm"
            >
              <span>{t.description || t.categories?.name || 'Transação'}</span>
              <span className={t.type === 'expense' ? 'text-red-400' : 'text-emerald-400'}>
                {t.type === 'expense' ? '-' : '+'}R$ {Number(t.amount).toFixed(2)}
              </span>
            </li>
          ))}
          {(!transactions || transactions.length === 0) && (
            <p className="text-neutral-500 text-sm">Nenhuma transação este mês ainda.</p>
          )}
        </ul>
      </div>
    </div>
  );
}
