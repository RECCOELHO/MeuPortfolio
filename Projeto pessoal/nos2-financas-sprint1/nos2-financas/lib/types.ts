export type CategoryScope = 'shared' | 'personal';
export type TransactionType = 'expense' | 'income';
export type TransactionVisibility = 'shared' | 'private';
export type TransactionSource = 'manual' | 'chat';

export interface Category {
  id: string;
  household_id: string;
  name: string;
  icon: string | null;
  monthly_budget: number | null;
  scope: CategoryScope;
  owner_user_id: string | null;
  created_at: string;
}

export interface Transaction {
  id: string;
  household_id: string;
  user_id: string;
  category_id: string | null;
  type: TransactionType;
  amount: number;
  description: string | null;
  notes: string | null;
  visibility: TransactionVisibility;
  source: TransactionSource;
  installment_group_id: string | null;
  installment_current: number | null;
  installment_total: number | null;
  occurred_at: string;
  created_at: string;
}

export interface CategoryRule {
  id: string;
  household_id: string;
  keyword: string;
  category_id: string;
}
