import { createClient } from '@/lib/supabase/server';
import type { Categorizer, CategorySuggestion } from './categorizer';

function normalize(text: string): string {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '') // remove acentos
    .trim();
}

/** Extrai a "palavra-chave" de uma descrição de transação, removendo números
 * (ex: "mercado 50" -> "mercado"). Usado ao aprender uma regra nova. */
export function extractKeyword(description: string): string {
  return normalize(description.replace(/[0-9]/g, '')).replace(/\s+/g, ' ').trim();
}

export const rulesEngine: Categorizer = {
  async suggest(description, householdId): Promise<CategorySuggestion> {
    if (!description) return { categoryId: null, matchedKeyword: null };

    const supabase = await createClient();
    const { data: rules } = await supabase
      .from('category_rules')
      .select('keyword, category_id')
      .eq('household_id', householdId);

    if (!rules || rules.length === 0) {
      return { categoryId: null, matchedKeyword: null };
    }

    const normalizedDescription = normalize(description);

    // Regra com palavra-chave mais longa/específica ganha em caso de empate
    const sorted = [...rules].sort((a, b) => b.keyword.length - a.keyword.length);

    for (const rule of sorted) {
      if (normalizedDescription.includes(rule.keyword)) {
        return { categoryId: rule.category_id, matchedKeyword: rule.keyword };
      }
    }

    return { categoryId: null, matchedKeyword: null };
  },

  async learn(keyword, categoryId, householdId) {
    if (!keyword) return;

    const supabase = await createClient();
    await supabase.from('category_rules').upsert(
      { household_id: householdId, keyword: normalize(keyword), category_id: categoryId },
      { onConflict: 'household_id,keyword' }
    );
  },
};
