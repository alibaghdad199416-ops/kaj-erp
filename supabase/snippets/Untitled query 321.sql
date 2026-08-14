select
  id,
  email,
  email_confirmed_at,
  created_at
from auth.users
where id = 'cdd35868-783d-4338-a418-0a8597503931'
   or lower(email) = lower('ajkinbaghdad@gmail.com');