-- Categorias padrão iniciais para o household do casal.
-- Ajuste o UUID abaixo se o household criado no Sprint 0 tiver outro id.
insert into categories (household_id, name, icon, scope) values
  ('00000000-0000-0000-0000-000000000001', 'Mercado', '🛒', 'shared'),
  ('00000000-0000-0000-0000-000000000001', 'Delivery', '🍔', 'shared'),
  ('00000000-0000-0000-0000-000000000001', 'Transporte', '🚗', 'shared'),
  ('00000000-0000-0000-0000-000000000001', 'Contas Fixas', '🧾', 'shared'),
  ('00000000-0000-0000-0000-000000000001', 'Lazer', '🎉', 'shared'),
  ('00000000-0000-0000-0000-000000000001', 'Saúde', '💊', 'shared'),
  ('00000000-0000-0000-0000-000000000001', 'Salário', '💰', 'shared')
on conflict do nothing;
