'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';

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

export async function createCategory(formData: FormData) {
  const { supabase, user, householdId } = await getCurrentUserAndHousehold();

  const name = (formData.get('name') as string)?.trim();
  if (!name) throw new Error('Nome da categoria é obrigatório');

  const icon = (formData.get('icon') as string) || null;
  const monthlyBudgetRaw = formData.get('monthly_budget') as string;
  const monthlyBudget = monthlyBudgetRaw ? Number(monthlyBudgetRaw) : null;
  const scope = (formData.get('scope') as 'shared' | 'personal') || 'shared';

  const { error } = await supabase.from('categories').insert({
    household_id: householdId,
    name,
    icon,
    monthly_budget: monthlyBudget,
    scope,
    owner_user_id: scope === 'personal' ? user.id : null,
  });

  if (error) throw new Error(error.message);
  revalidatePath('/categorias');
  revalidatePath('/transacoes');
}

export async function updateCategory(id: string, formData: FormData) {
  const { supabase } = await getCurrentUserAndHousehold();

  const name = (formData.get('name') as string)?.trim();
  const icon = (formData.get('icon') as string) || null;
  const monthlyBudgetRaw = formData.get('monthly_budget') as string;
  const monthlyBudget = monthlyBudgetRaw ? Number(monthlyBudgetRaw) : null;

  const { error } = await supabase
    .from('categories')
    .update({ name, icon, monthly_budget: monthlyBudget })
    .eq('id', id);

  if (error) throw new Error(error.message);
  revalidatePath('/categorias');
}

export async function deleteCategory(id: string) {
  const { supabase } = await getCurrentUserAndHousehold();

  const { error } = await supabase.from('categories').delete().eq('id', id);
  if (error) throw new Error(error.message);
  revalidatePath('/categorias');
  revalidatePath('/transacoes');
}
