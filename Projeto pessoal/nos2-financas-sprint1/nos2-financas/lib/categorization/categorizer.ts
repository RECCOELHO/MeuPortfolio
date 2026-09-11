export interface CategorySuggestion {
  categoryId: string | null;
  matchedKeyword: string | null;
}

/**
 * Qualquer estratégia de categorização (regras hoje, IA amanhã) implementa
 * esta interface. O resto do app depende só disso — trocar a implementação
 * não exige mudar nada fora deste módulo.
 */
export interface Categorizer {
  suggest(description: string, householdId: string): Promise<CategorySuggestion>;
  learn(keyword: string, categoryId: string, householdId: string): Promise<void>;
}
