-- Office stock: items, movements (withdraw / receive / adjust), users, summary views.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  role text not null default 'staff' check (role in ('admin','staff')),
  active boolean not null default false,
  created_at timestamptz not null default now()
);

-- First user to sign up becomes an active admin; everyone after must be activated by an admin.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare first_user boolean;
begin
  select not exists (select 1 from public.profiles) into first_user;
  insert into public.profiles(id, email, display_name, role, active)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)),
          case when first_user then 'admin' else 'staff' end, first_user);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.is_active() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select active from public.profiles where id = auth.uid()), false) $$;
create function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select active and role = 'admin' from public.profiles where id = auth.uid()), false) $$;

create table public.items (
  code text primary key,
  name text not null,
  qty numeric not null default 0,
  unit text not null default '',
  min_qty numeric not null default 0,
  category text not null default '',
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table public.movements (
  id bigint generated always as identity primary key,
  ts timestamptz not null default now(),
  type text not null check (type in ('OUT','IN','ADJUST','NEW')),
  code text not null references public.items(code) on update cascade,
  qty numeric not null,            -- OUT/IN: positive amount; ADJUST: signed change
  balance_after numeric,
  actor text not null default '',  -- who withdrew / received
  dept text not null default '',
  note text not null default '',
  created_by uuid default auth.uid()
);
create index movements_ts_idx on public.movements (ts desc);
create index movements_code_idx on public.movements (code, ts desc);

-- Keeps items.qty in step with every movement and refuses to go below zero.
create function public.apply_movement() returns trigger
language plpgsql security definer set search_path = public as $$
declare cur numeric;
begin
  select qty into cur from public.items where code = new.code for update;
  if new.type = 'OUT' then
    if new.qty <= 0 then raise exception 'จำนวนต้องมากกว่า 0'; end if;
    if cur < new.qty then raise exception 'สต็อกไม่พอ: % คงเหลือ % แต่เบิก %', new.code, cur, new.qty; end if;
    cur := cur - new.qty;
  elsif new.type = 'IN' then
    if new.qty <= 0 then raise exception 'จำนวนต้องมากกว่า 0'; end if;
    cur := cur + new.qty;
  elsif new.type = 'ADJUST' then
    if cur + new.qty < 0 then raise exception 'ปรับแล้วสต็อกติดลบ'; end if;
    cur := cur + new.qty;
  end if;
  update public.items set qty = cur, updated_at = now() where code = new.code;
  new.balance_after := cur;
  return new;
end $$;
create trigger trg_apply_movement before insert on public.movements
  for each row execute function public.apply_movement();

-- Edit stock by counting: pass the real quantity, an ADJUST movement records the difference.
create function public.set_stock(p_code text, p_new_qty numeric, p_note text default '')
returns numeric language plpgsql security invoker set search_path = public as $$
declare cur numeric;
begin
  if p_new_qty < 0 then raise exception 'จำนวนต้องไม่ติดลบ'; end if;
  select qty into cur from public.items where code = p_code;
  if cur is null then raise exception 'ไม่พบสินค้า %', p_code; end if;
  insert into public.movements(type, code, qty, actor, note)
  values ('ADJUST', p_code, p_new_qty - cur,
          coalesce((select display_name from public.profiles where id = auth.uid()), ''), p_note);
  return p_new_qty;
end $$;

-- Summary views (run with the caller's rights so RLS applies)
create view public.v_item_status with (security_invoker = true) as
select i.*, (i.qty <= i.min_qty and i.min_qty > 0) as low,
       (select max(ts) from public.movements m where m.code = i.code and m.type = 'OUT') as last_out
from public.items i;

create view public.v_daily with (security_invoker = true) as
select (ts at time zone 'Asia/Bangkok')::date as day,
       coalesce(sum(qty) filter (where type = 'OUT'), 0) as out_qty,
       coalesce(sum(qty) filter (where type = 'IN'), 0) as in_qty,
       count(*) filter (where type = 'OUT') as out_count,
       count(*) filter (where type = 'IN') as in_count
from public.movements group by 1;

create view public.v_monthly_by_item with (security_invoker = true) as
select to_char(ts at time zone 'Asia/Bangkok', 'YYYY-MM') as month, m.code, i.name, i.unit, i.category,
       coalesce(sum(m.qty) filter (where m.type = 'OUT'), 0) as out_qty,
       coalesce(sum(m.qty) filter (where m.type = 'IN'), 0) as in_qty
from public.movements m join public.items i using (code)
where m.type in ('OUT','IN') group by 1, 2, 3, 4, 5;

-- Row level security: only active users, admins for edits.
alter table public.profiles enable row level security;
alter table public.items enable row level security;
alter table public.movements enable row level security;

create policy profiles_self on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy profiles_admin_update on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy items_read on public.items for select to authenticated using (public.is_active());
create policy items_admin_write on public.items for insert to authenticated with check (public.is_admin());
create policy items_admin_update on public.items for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy mov_read on public.movements for select to authenticated using (public.is_active());
create policy mov_insert on public.movements for insert to authenticated
  with check (public.is_active() and (type in ('OUT','IN') or public.is_admin()));

revoke all on function public.set_stock(text, numeric, text) from public, anon;
grant execute on function public.set_stock(text, numeric, text) to authenticated;
revoke all on function public.handle_new_user(), public.apply_movement() from public, anon, authenticated;
revoke all on function public.is_active(), public.is_admin() from public, anon;
grant execute on function public.is_active(), public.is_admin() to authenticated;
