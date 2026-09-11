'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { rulesEngine, extractKeyword } from '@/lib/categorization/rules-engine';

async function getCurrentUserAndHousehold() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error('Não autenticado');

  const { data: profile } = await supabase
    .from('users')
    .select('household_id')
    .eq('id', user.id)
    .single();
  if (!profile) throw new Error('Usuário sem household associado');

  return { supabase, user, householdId: profile.household_id as string };
}

export interface CreateTransactionResult {
  categoryId: string | null;
  suggested: boolean;
}

export async function createTransaction(formData: FormData): Promise<CreateTransactionResult> {
  const { supabase, user, householdId } = await getCurrentUserAndHousehold();

  const description = (formData.get('description') as string)?.trim() || null;
  const amount = Number(formData.get('amount'));
  if (!amount || amount <= 0) throw new Error('Valor inválido');

  const type = (formData.get('type') as 'expense' | 'income') || 'expense';
  const notes = (formData.get('notes') as string) || null;
  const visibility = (formData.get('visibility') as 'shared' | 'private') || 'shared';
  let categoryId = (formData.get('category_id') as string) || null;

  // Se nenhuma categoria foi escolhida manualmente, tenta sugerir por regra aprendida
  let suggested = false;
  if (!categoryId && description) {
    const suggestion = await rulesEngine.suggest(description, householdId);
    if (suggestion.categoryId) {
      categoryId = suggestion.categoryId;
      suggested = true;
    }
  }

  const { error } = await supabase.from('transactions').insert({
    household_id: householdId,
    user_id: user.id,
    category_id: categoryId,
    type,
    amount,
    description,
    notes,
    visibility,
    source: 'manual',
    occurred_at: new Date().toISOString().slice(0, 10),
  });

  if (error) throw new Error(error.message);

  // Categoria foi escolhida manualmente (não veio de sugestão automática) ->
  // aprende essa palavra-chave para a próxima vez que aparecer algo parecido.
  if (categoryId && !suggested && description) {
    await rulesEngine.learn(extractKeyword(description), categoryId, householdId);
  }

  revalidatePath('/transacoes');
  revalidatePath('/dashboard');

  return { categoryId, suggested };
}

export async function deleteTransaction(id: string) {
  const { supabase } = await getCurrentUserAndHousehold();

  const { error } = await supabase.from('transactions').delete().eq('id', id);
  if (error) throw new Error(error.message);
  revalidatePath('/transacoes');
  revalidatePath('/dashboard');
}
