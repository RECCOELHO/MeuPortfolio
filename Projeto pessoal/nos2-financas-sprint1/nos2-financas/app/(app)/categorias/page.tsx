import { createClient } from '@/lib/supabase/server';
import { createCategory, deleteCategory } from '@/app/actions/categories';

export default async function CategoriasPage() {
  const supabase = await createClient();
  const { data: categories } = await supabase.from('categories').select('*').order('name');

  return (
    <div className="p-6 max-w-2xl mx-auto space-y-8">
      <h1 className="text-2xl font-semibold">Categorias</h1>

      <form action={createCategory} className="space-y-3 border border-neutral-800 rounded-lg p-4">
        <input
          name="name"
          placeholder="Nome (ex: Mercado)"
          required
          className="w-full bg-neutral-900 rounded px-3 py-2"
        />
        <input name="icon" placeholder="Ícone (emoji, opcional)" className="w-full bg-neutral-900 rounded px-3 py-2" />
        <input
          name="monthly_budget"
          type="number"
          step="0.01"
          placeholder="Orçamento mensal (opcional)"
          className="w-full bg-neutral-900 rounded px-3 py-2"
        />
        <select name="scope" defaultValue="shared" className="w-full bg-neutral-900 rounded px-3 py-2">
          <option value="shared">Compartilhada (casal)</option>
          <option value="personal">Pessoal (só minha)</option>
        </select>
        <button type="submit" className="bg-emerald-600 rounded px-4 py-2 font-medium">
          Adicionar categoria
        </button>
      </form>

      <ul className="space-y-2">
        {categories?.map((c) => (
          <li
            key={c.id}
            className="flex items-center justify-between border border-neutral-800 rounded-lg px-4 py-3"
          >
            <span>
              {c.icon ? `${c.icon} ` : ''}
              {c.name}
              <span className="text-neutral-500 text-sm ml-2">
                {c.scope === 'personal' ? '(pessoal)' : '(compartilhada)'}
                {c.monthly_budget ? ` · orçamento R$${c.monthly_budget}` : ''}
              </span>
            </span>
            <form action={deleteCategory.bind(null, c.id)}>
              <button className="text-red-400 text-sm">remover</button>
            </form>
          </li>
        ))}
        {(!categories || categories.length === 0) && (
          <p className="text-neutral-500 text-sm">Nenhuma categoria ainda. Adicione a primeira acima.</p>
        )}
      </ul>
    </div>
  );
}
