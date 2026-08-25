begin;

create extension if not exists pgcrypto;

create table if not exists public.erp_hr_departments (
  id uuid primary key default gen_random_uuid(), company_id uuid not null,
  code text not null, name_ar text not null, name_en text not null default '',
  parent_id uuid, manager_employee_id uuid, cost_center_id uuid,
  is_active boolean not null default true, is_deleted boolean not null default false,
  deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(company_id, code)
);
create table if not exists public.erp_hr_employees (
  id uuid primary key default gen_random_uuid(), company_id uuid not null,
  employee_number text not null, first_name_ar text not null, last_name_ar text not null default '',
  first_name_en text not null default '', last_name_en text not null default '', department_id uuid,
  job_title_ar text not null default '', job_title_en text not null default '', hire_date date not null,
  employment_status text not null default 'active', phone text, email text, national_id text,
  bank_account text, basic_salary numeric(18,2) not null default 0, currency_code text not null default 'IQD',
  user_id uuid, notes text, is_deleted boolean not null default false, deleted_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(company_id, employee_number)
);
create table if not exists public.erp_hr_employment_contracts (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, employee_id uuid not null,
  contract_number text not null, contract_type text not null default 'permanent', start_date date not null,
  end_date date, probation_end_date date, basic_salary numeric(18,2) not null default 0,
  housing_allowance numeric(18,2) not null default 0, transport_allowance numeric(18,2) not null default 0,
  other_allowance numeric(18,2) not null default 0, working_hours_per_week numeric(8,2) not null default 40,
  status text not null default 'active', document_id uuid, is_deleted boolean not null default false,
  deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(company_id, contract_number)
);
create table if not exists public.erp_hr_attendance_records (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, employee_id uuid not null,
  attendance_date date not null, check_in_at timestamptz, check_out_at timestamptz,
  worked_minutes integer not null default 0, overtime_minutes integer not null default 0,
  status text not null default 'present', source text not null default 'manual', notes text,
  is_deleted boolean not null default false, deleted_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(company_id, employee_id, attendance_date)
);
create table if not exists public.erp_hr_leave_requests (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, employee_id uuid not null,
  leave_type text not null, start_date date not null, end_date date not null,
  total_days numeric(8,2) not null default 0, status text not null default 'draft', reason text,
  approver_user_id uuid, decision_at timestamptz, is_deleted boolean not null default false,
  deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.erp_hr_payroll_runs (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, payroll_number text not null,
  period_start date not null, period_end date not null, status text not null default 'draft',
  gross_amount numeric(18,2) not null default 0, deduction_amount numeric(18,2) not null default 0,
  net_amount numeric(18,2) not null default 0, journal_entry_id uuid, created_by uuid,
  approved_by uuid, approved_at timestamptz, is_deleted boolean not null default false,
  deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(company_id, payroll_number), unique(company_id, period_start, period_end)
);
create table if not exists public.erp_hr_payroll_items (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, payroll_run_id uuid not null,
  employee_id uuid not null, basic_salary numeric(18,2) not null default 0,
  allowances numeric(18,2) not null default 0, overtime_amount numeric(18,2) not null default 0,
  deductions numeric(18,2) not null default 0, net_salary numeric(18,2) not null default 0,
  attendance_days numeric(8,2) not null default 0, leave_days numeric(8,2) not null default 0,
  metadata_json jsonb not null default '{}'::jsonb, is_deleted boolean not null default false,
  deleted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(company_id, payroll_run_id, employee_id)
);

create index if not exists idx_erp_hr_employee_company on public.erp_hr_employees(company_id, employment_status) where not is_deleted;
create index if not exists idx_erp_hr_attendance_day on public.erp_hr_attendance_records(company_id, attendance_date) where not is_deleted;
create index if not exists idx_erp_hr_leave_status on public.erp_hr_leave_requests(company_id, status) where not is_deleted;

-- Existing project helper used by prior migrations; all functions also verify the requested tenant.
create or replace function public.erp_cloud_hr_dashboard_summary(p_company_id uuid, p_day date)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  return jsonb_build_object(
    'activeEmployees',(select count(*) from erp_hr_employees where company_id=p_company_id and not is_deleted and employment_status='active'),
    'presentToday',(select count(*) from erp_hr_attendance_records where company_id=p_company_id and not is_deleted and attendance_date=p_day and status='present'),
    'pendingLeaves',(select count(*) from erp_hr_leave_requests where company_id=p_company_id and not is_deleted and status='pending'),
    'openPayrollRuns',(select count(*) from erp_hr_payroll_runs where company_id=p_company_id and not is_deleted and status in ('draft','pending'))
  );
end $$;

create or replace function public.erp_list_cloud_hr_employees(p_company_id uuid)
returns table(id uuid,"employeeNumber" text,"firstNameAr" text,"lastNameAr" text,"jobTitleAr" text,"departmentName" text,"basicSalary" numeric,"currencyCode" text,"employmentStatus" text)
language sql security definer set search_path=public as $$
  select e.id,e.employee_number,e.first_name_ar,e.last_name_ar,e.job_title_ar,d.name_ar,e.basic_salary,e.currency_code,e.employment_status
  from erp_hr_employees e left join erp_hr_departments d on d.id=e.department_id and d.company_id=e.company_id and not d.is_deleted
  where e.company_id=p_company_id and not e.is_deleted and public.erp_active_company_context(p_company_id) is not null
  order by e.employee_number;
$$;

create or replace function public.erp_create_cloud_hr_employee(p_company_id uuid,p_employee_number text,p_first_name_ar text,p_last_name_ar text,p_job_title_ar text,p_basic_salary numeric,p_hire_date date)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_department uuid;
begin
  perform public.erp_active_company_context(p_company_id);
  if coalesce(trim(p_employee_number),'')='' or coalesce(trim(p_first_name_ar),'')='' or p_basic_salary<0 then raise exception 'Invalid employee data'; end if;
  select id into v_department from erp_hr_departments where company_id=p_company_id and code='ADMIN' and not is_deleted limit 1;
  if v_department is null then
    insert into erp_hr_departments(company_id,code,name_ar,name_en) values(p_company_id,'ADMIN','الإدارة','Administration') returning id into v_department;
  end if;
  insert into erp_hr_employees(company_id,employee_number,first_name_ar,last_name_ar,department_id,job_title_ar,hire_date,basic_salary)
  values(p_company_id,trim(p_employee_number),trim(p_first_name_ar),coalesce(trim(p_last_name_ar),''),v_department,coalesce(trim(p_job_title_ar),''),p_hire_date,p_basic_salary)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.erp_generate_cloud_payroll(p_company_id uuid,p_period_start date,p_period_end date)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_run uuid; v_number text; v_gross numeric(18,2);
begin
  perform public.erp_active_company_context(p_company_id);
  if p_period_end<p_period_start then raise exception 'Invalid payroll period'; end if;
  perform pg_advisory_xact_lock(hashtext(p_company_id::text||p_period_start::text||p_period_end::text));
  if exists(select 1 from erp_hr_payroll_runs where company_id=p_company_id and period_start=p_period_start and period_end=p_period_end and not is_deleted) then raise exception 'Payroll already exists for period'; end if;
  v_number := 'PAY-'||to_char(p_period_start,'YYYYMM')||'-'||substr(replace(gen_random_uuid()::text,'-',''),1,8);
  insert into erp_hr_payroll_runs(company_id,payroll_number,period_start,period_end,created_by)
  values(p_company_id,v_number,p_period_start,p_period_end,auth.uid()) returning id into v_run;
  insert into erp_hr_payroll_items(company_id,payroll_run_id,employee_id,basic_salary,allowances,overtime_amount,deductions,net_salary,attendance_days,leave_days)
  select p_company_id,v_run,e.id,e.basic_salary,0,0,0,e.basic_salary,
    (select count(*) from erp_hr_attendance_records a where a.company_id=p_company_id and a.employee_id=e.id and not a.is_deleted and a.attendance_date between p_period_start and p_period_end and a.status='present'),
    (select coalesce(sum(greatest(0,least(l.end_date,p_period_end)-greatest(l.start_date,p_period_start)+1)),0) from erp_hr_leave_requests l where l.company_id=p_company_id and l.employee_id=e.id and not l.is_deleted and l.status='approved' and l.start_date<=p_period_end and l.end_date>=p_period_start)
  from erp_hr_employees e where e.company_id=p_company_id and not e.is_deleted and e.employment_status='active';
  select coalesce(sum(net_salary),0) into v_gross from erp_hr_payroll_items where payroll_run_id=v_run and not is_deleted;
  update erp_hr_payroll_runs set gross_amount=v_gross,net_amount=v_gross,updated_at=now() where id=v_run;
  return v_run;
end $$;

create or replace function public.erp_save_cloud_hr_attendance(p_company_id uuid,p_employee_id uuid,p_attendance_date date,p_status text,p_check_in_at timestamptz default null,p_check_out_at timestamptz default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_minutes integer:=0;
begin
  perform public.erp_active_company_context(p_company_id);
  if not exists(select 1 from erp_hr_employees where id=p_employee_id and company_id=p_company_id and not is_deleted) then raise exception 'Employee not found'; end if;
  if p_check_in_at is not null and p_check_out_at is not null then v_minutes:=greatest(0,extract(epoch from (p_check_out_at-p_check_in_at))/60)::integer; end if;
  insert into erp_hr_attendance_records(company_id,employee_id,attendance_date,status,check_in_at,check_out_at,worked_minutes,notes)
  values(p_company_id,p_employee_id,p_attendance_date,p_status,p_check_in_at,p_check_out_at,v_minutes,p_notes)
  on conflict(company_id,employee_id,attendance_date) do update set status=excluded.status,check_in_at=excluded.check_in_at,check_out_at=excluded.check_out_at,worked_minutes=excluded.worked_minutes,notes=excluded.notes,is_deleted=false,deleted_at=null,updated_at=now()
  returning id into v_id; return v_id;
end $$;

create or replace function public.erp_create_cloud_hr_leave_request(p_company_id uuid,p_employee_id uuid,p_leave_type text,p_start_date date,p_end_date date,p_reason text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  perform public.erp_active_company_context(p_company_id);
  if p_end_date<p_start_date then raise exception 'Invalid leave period'; end if;
  if not exists(select 1 from erp_hr_employees where id=p_employee_id and company_id=p_company_id and not is_deleted) then raise exception 'Employee not found'; end if;
  insert into erp_hr_leave_requests(company_id,employee_id,leave_type,start_date,end_date,total_days,status,reason)
  values(p_company_id,p_employee_id,p_leave_type,p_start_date,p_end_date,(p_end_date-p_start_date+1),'pending',p_reason) returning id into v_id; return v_id;
end $$;

create or replace function public.erp_decide_cloud_hr_leave_request(p_company_id uuid,p_leave_request_id uuid,p_approve boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  update erp_hr_leave_requests set status=case when p_approve then 'approved' else 'rejected' end,approver_user_id=auth.uid(),decision_at=now(),updated_at=now()
  where id=p_leave_request_id and company_id=p_company_id and not is_deleted and status='pending';
  if not found then raise exception 'Pending leave request not found'; end if;
end $$;

alter table erp_hr_departments enable row level security;
alter table erp_hr_employees enable row level security;
alter table erp_hr_employment_contracts enable row level security;
alter table erp_hr_attendance_records enable row level security;
alter table erp_hr_leave_requests enable row level security;
alter table erp_hr_payroll_runs enable row level security;
alter table erp_hr_payroll_items enable row level security;

do $$ declare t text; begin
 foreach t in array array['erp_hr_departments','erp_hr_employees','erp_hr_employment_contracts','erp_hr_attendance_records','erp_hr_leave_requests','erp_hr_payroll_runs','erp_hr_payroll_items'] loop
  execute format('drop policy if exists tenant_access on public.%I',t);
  execute format('create policy tenant_access on public.%I for all using (public.erp_active_company_context(company_id) is not null) with check (public.erp_active_company_context(company_id) is not null)',t);
 end loop;
end $$;

commit;
