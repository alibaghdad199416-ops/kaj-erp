select
  m.id as membership_id,
  m.company_id,
  m.user_id,
  m.user_uid,
  m.user_email,
  m.local_user_id,
  m.default_branch_id,
  m.role_code,
  m.is_system_admin,
  m.is_active,
  u.id as auth_user_id,
  u.email as auth_email
from public.company_memberships m
left join auth.users u on u.id = m.user_id
where m.company_id = '11111111-1111-4111-8111-111111111111'
  and lower(trim(m.user_email)) = lower('ajkinbaghdad@gmail.com');