import { createClient } from '@/lib/supabase/server';
import { deleteTransaction } from '@/app/actions/transactions';
import { TransactionForm } from '@/components/transaction-form';

export default async function TransacoesPage() {
  const supabase = await createClient();

  const { data: categories } = await supabase
    .from('categories')
    .select('id, name, icon')
    .order('name');

  // RLS já filtra automaticamente: transações 'private' de outro usuário
  // nem chegam nessa consulta.
  const { data: transactions } = await supabase
    .from('transactions')
    .select('id, description, amount, type, occurred_at, notes, visibility, categories(name, icon)')
    .order('occurred_at', { ascending: false })
    .limit(50);

  return (
    <div className="p-6 max-w-2xl mx-auto space-y-8">
      <h1 className="text-2xl font-semibold">Transações</h1>

      <TransactionForm categories={categories ?? []} />

      <ul className="space-y-2">
        {transactions?.map((t) => (
          <li
            key={t.id}
            className="flex items-center justify-between border border-neutral-800 rounded-lg px-4 py-3"
          >
            <div>
              <p className="font-medium">
                {t.description || '(sem descrição)'}
                {t.visibility === 'private' && (
                  <span className="text-neutral-500 text-xs ml-2">🔒 privado</span>
                )}
              </p>
              <p className="text-sm text-neutral-500">
                {t.categories?.name ?? 'Sem categoria'} · {new Date(t.occurred_at).toLocaleDateString('pt-BR')}
              </p>
              {t.notes && <p className="text-xs text-neutral-600 mt-1">{t.notes}</p>}
            </div>
            <div className="flex items-center gap-3">
              <span className={t.type === 'expense' ? 'text-red-400' : 'text-emerald-400'}>
                {t.type === 'expense' ? '-' : '+'}R$ {Number(t.amount).toFixed(2)}
              </span>
              <form action={deleteTransaction.bind(null, t.id)}>
                <button className="text-neutral-500 text-sm">remover</button>
              </form>
            </div>
          </li>
        ))}
        {(!transactions || transactions.length === 0) && (
          <p className="text-neutral-500 text-sm">Nenhuma transação ainda.</p>
        )}
      </ul>
    </div>
  );
}
