'use client';

import { useState, useTransition } from 'react';
import { createTransaction } from '@/app/actions/transactions';

interface CategoryOption {
  id: string;
  name: string;
  icon: string | null;
}

interface Props {
  categories: CategoryOption[];
}

export function TransactionForm({ categories }: Props) {
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [isPending, startTransition] = useTransition();
  const [feedback, setFeedback] = useState<string | null>(null);
  const [formKey, setFormKey] = useState(0);

  function handleSubmit(formData: FormData) {
    startTransition(async () => {
      const result = await createTransaction(formData);

      if (result.categoryId && result.suggested) {
        const cat = categories.find((c) => c.id === result.categoryId);
        setFeedback(`Categorizado automaticamente como "${cat?.name ?? '—'}" ✅`);
      } else {
        setFeedback('Transação registrada ✅');
      }

      setFormKey((k) => k + 1); // reseta os campos do formulário
      setTimeout(() => setFeedback(null), 4000);
    });
  }

  return (
    <form key={formKey} action={handleSubmit} className="space-y-3 border border-neutral-800 rounded-lg p-4">
      <div className="flex gap-2">
        <input
          name="description"
          placeholder="Ex: mercado"
          required
          className="flex-1 bg-neutral-900 rounded px-3 py-2"
        />
        <input
          name="amount"
          type="number"
          step="0.01"
          min="0.01"
          placeholder="Valor"
          required
          className="w-28 bg-neutral-900 rounded px-3 py-2"
        />
      </div>

      <div className="flex items-center gap-2">
        <select name="type" defaultValue="expense" className="bg-neutral-900 rounded px-3 py-2">
          <option value="expense">Gasto</option>
          <option value="income">Receita</option>
        </select>
        <button
          type="button"
          onClick={() => setShowAdvanced((v) => !v)}
          className="text-sm text-neutral-400 underline ml-auto"
        >
          {showAdvanced ? 'ocultar detalhes' : 'mais detalhes'}
        </button>
      </div>

      {showAdvanced && (
        <div className="space-y-2 border-t border-neutral-800 pt-3">
          <select name="category_id" defaultValue="" className="w-full bg-neutral-900 rounded px-3 py-2">
            <option value="">Deixar a categorização automática decidir</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.icon ? `${c.icon} ` : ''}
                {c.name}
              </option>
            ))}
          </select>
          <textarea
            name="notes"
            placeholder="Anotação (opcional)"
            className="w-full bg-neutral-900 rounded px-3 py-2"
          />
          <select name="visibility" defaultValue="shared" className="w-full bg-neutral-900 rounded px-3 py-2">
            <option value="shared">Visível pro casal</option>
            <option value="private">Só eu vejo</option>
          </select>
        </div>
      )}

      <button
        type="submit"
        disabled={isPending}
        className="bg-emerald-600 hover:bg-emerald-500 transition-colors rounded px-4 py-2 font-medium disabled:opacity-50"
      >
        {isPending ? 'Salvando...' : 'Registrar'}
      </button>

      {feedback && <p className="text-sm text-emerald-400">{feedback}</p>}
    </form>
  );
}
