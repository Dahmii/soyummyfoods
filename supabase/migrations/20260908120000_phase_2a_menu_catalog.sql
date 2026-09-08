-- Phase 2A: menu catalogue foundation. Product images retain existing local paths
-- until Storage migration is explicitly introduced in a later phase.

create type public.product_status as enum ('draft', 'active', 'archived');

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null check (btrim(name) <> ''),
  slug text not null unique check (btrim(slug) <> ''),
  description text,
  is_active boolean not null default true,
  display_order integer not null check (display_order >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  updated_by uuid references public.profiles (id) on delete set null
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories (id) on delete restrict,
  slug text not null unique check (btrim(slug) <> ''),
  name text not null check (btrim(name) <> ''),
  description text not null check (btrim(description) <> ''),
  base_price numeric(10, 2),
  sale_price numeric(10, 2),
  price_on_request boolean not null default false,
  portion_note text,
  prep_time_minutes integer not null check (prep_time_minutes > 0),
  status public.product_status not null default 'draft',
  is_available boolean not null default true,
  tags text[] not null default '{}',
  display_order integer not null check (display_order >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles (id) on delete set null,
  updated_by uuid references public.profiles (id) on delete set null,
  constraint products_base_price_nonnegative check (base_price is null or base_price >= 0),
  constraint products_sale_price_nonnegative check (sale_price is null or sale_price >= 0),
  constraint products_price_request_base_price check (
    (price_on_request and base_price is null and sale_price is null)
    or (not price_on_request and base_price is not null)
  ),
  constraint products_sale_price_not_above_base_price check (
    sale_price is null or sale_price <= base_price
  ),
  constraint products_supported_tags check (
    tags <@ array['popular', 'new', 'special']::text[]
  )
);

create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  storage_path text not null check (btrim(storage_path) <> ''),
  alt_text text,
  is_primary boolean not null default false,
  display_order integer not null default 0 check (display_order >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, storage_path)
);

create index categories_active_display_order_idx
  on public.categories (display_order) where is_active;
create index products_category_display_order_idx on public.products (category_id, display_order);
create index products_public_menu_idx on public.products (display_order) where status = 'active';
create index product_images_product_display_order_idx on public.product_images (product_id, display_order);
create unique index product_images_one_primary_per_product_idx
  on public.product_images (product_id) where is_primary;

create trigger categories_set_updated_at_before_update
before update on public.categories
for each row execute function public.set_updated_at();

create trigger products_set_updated_at_before_update
before update on public.products
for each row execute function public.set_updated_at();

create trigger product_images_set_updated_at_before_update
before update on public.product_images
for each row execute function public.set_updated_at();

alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;

revoke all on table public.categories from anon, authenticated;
revoke all on table public.products from anon, authenticated;
revoke all on table public.product_images from anon, authenticated;

grant select on table public.categories to anon;
grant select on table public.products to anon;
grant select on table public.product_images to anon;
grant select, insert, update, delete on table public.categories to authenticated;
grant select, insert, update, delete on table public.products to authenticated;
grant select, insert, update, delete on table public.product_images to authenticated;

create policy "categories_public_read_active"
on public.categories for select to anon, authenticated
using (is_active);
create policy "categories_manager_owner_manage"
on public.categories for all to authenticated
using (public.is_manager_or_owner())
with check (public.is_manager_or_owner());

create policy "products_public_read_active"
on public.products for select to anon, authenticated
using (status = 'active'::public.product_status);
create policy "products_manager_owner_manage"
on public.products for all to authenticated
using (public.is_manager_or_owner())
with check (public.is_manager_or_owner());

create policy "product_images_public_read_active_product"
on public.product_images for select to anon, authenticated
using (
  exists (
    select 1 from public.products
    where products.id = product_images.product_id
      and products.status = 'active'::public.product_status
  )
);
create policy "product_images_manager_owner_manage"
on public.product_images for all to authenticated
using (public.is_manager_or_owner())
with check (public.is_manager_or_owner());

insert into public.categories (name, slug, display_order)
values
  ('Rice Dishes', 'rice-dishes', 0),
  ('Beans Dishes', 'beans-dishes', 1),
  ('Yam Dishes', 'yam-dishes', 2),
  ('Starters & Sides', 'starters-sides', 3),
  ('Pepper Soups', 'pepper-soups', 4),
  ('Soups & Stews', 'soups-stews', 5),
  ('Proteins', 'proteins', 6)
on conflict (slug) do update set
  name = excluded.name,
  display_order = excluded.display_order,
  updated_at = now();

with seed (
  category_slug, slug, name, description, base_price, price_on_request,
  portion_note, prep_time_minutes, is_available, tags, display_order
) as (
  values
    ('rice-dishes','jollof-rice','Jollof Rice','Our signature smoky party jollof, slow-simmered in rich tomato, pepper and traditional spices.',9,false,null,35,true,array['popular']::text[],0),
    ('rice-dishes','fried-rice','Fried Rice','Buttery long-grain rice tossed with garden vegetables, sweetcorn and seasoned stock.',10,false,null,35,true,array['popular']::text[],1),
    ('rice-dishes','white-rice-designer-stew','White Rice & Designer Stew','Fluffy steamed rice served with our slow-fried designer pepper stew.',12,false,null,40,true,array[]::text[],2),
    ('rice-dishes','white-rice-ayamase','White Rice & Ayamase Stew','Steamed rice with authentic ayamase — green pepper sauce cooked down in bleached palm oil.',15,false,null,45,true,array['popular']::text[],3),
    ('rice-dishes','ofada-rice-sauce','Ofada Rice & Sauce','Locally milled ofada rice wrapped in banana leaf, served with rich ayamase sauce and assorted meat.',15,false,null,45,true,array['special']::text[],4),
    ('rice-dishes','coconut-rice','Coconut Rice','Fragrant rice simmered in fresh coconut milk. Priced to portion — message the kitchen for a quote.',null,true,null,40,true,array[]::text[],5),
    ('rice-dishes','half-and-half-rice','Half & Half (Jollof & Fried)','Can’t choose? A split portion of our smoky jollof and party fried rice in one pack.',10,false,null,35,true,array['popular']::text[],6),
    ('beans-dishes','plain-beans','Plain Beans','Honey beans cooked soft and seasoned simply — a comforting everyday staple.',5,false,null,40,true,array[]::text[],7),
    ('beans-dishes','mashed-beans-palm-oil','Mashed Beans & Palm Oil Base','Beans mashed down and finished in a rich palm oil and pepper base with smoked fish.',12,false,null,45,true,array['popular']::text[],8),
    ('beans-dishes','mixed-beans','Mixed Beans','Beans cooked with plantain and peppers for a fuller, sweeter plate.',10,false,null,45,true,array[]::text[],9),
    ('yam-dishes','yam-porridge','Yam Porridge','Asaro — soft yam simmered down in palm oil, peppers and leafy greens until creamy.',12,false,null,45,true,array['popular']::text[],10),
    ('yam-dishes','yam-platter','Yam Platter','A generous platter of fried and boiled yam served with egg sauce and pepper stew.',19,false,null,45,true,array[]::text[],11),
    ('yam-dishes','yam-beans-sauce','Yam & Beans with Sauce','The classic pairing of yam and honey beans, finished with rich pepper sauce.',18,false,null,50,true,array[]::text[],12),
    ('yam-dishes','fish-platter','Fish Platter','Whole seasoned fish with fried yam or plantain and our house pepper sauce. Our biggest sharing plate.',25,false,null,55,true,array['special']::text[],13),
    ('starters-sides','meat-pie','Meat Pie','Buttery hand-crimped pastry filled with seasoned minced beef, potato and carrot.',2.5,false,null,15,true,array['popular']::text[],14),
    ('starters-sides','small-chops','Small Chops','Party pack of spring rolls and puff puff, fried fresh to order.',5,false,'Spring rolls & puff',20,true,array['popular']::text[],15),
    ('starters-sides','gizdodo','Gizdodo','Diced gizzard and sweet plantain tossed in a glossy bell pepper sauce.',8,false,null,25,true,array['new']::text[],16),
    ('starters-sides','moinmoin','Moinmoin','Steamed bean pudding with peppers and onion, wrapped and cooked traditionally.',2.5,false,null,40,true,array[]::text[],17),
    ('starters-sides','plantain','Plantain','Ripe plantain fried until the edges caramelise — dodo done properly.',3,false,null,12,true,array['popular']::text[],18),
    ('starters-sides','akara','Akara','Peeled bean fritters fried golden and crisp, light and fluffy inside.',5,false,'5 pcs',20,true,array['new']::text[],19),
    ('pepper-soups','goat-meat-pepper-soup','Goat Meat Pepper Soup','Fiery, aromatic broth of tender goat meat with uziza, scent leaf and pepper soup spices.',12,false,null,50,true,array['popular']::text[],20),
    ('pepper-soups','tilapia-pepper-soup','Tilapia Pepper Soup','Fresh tilapia poached in a light, peppery broth with herbs and scent leaf.',12,false,null,35,true,array['new']::text[],21),
    ('soups-stews','efo-riro','Efo-riro','Rich spinach stew simmered in palm oil with assorted meat, locust beans and peppers.',13,false,null,45,true,array['popular']::text[],22),
    ('soups-stews','egusi','Egusi','Ground melon seeds cooked with spinach, palm oil and assorted meats.',13,false,null,45,true,array['popular']::text[],23),
    ('soups-stews','mixed-okra','Mixed Okra','Chopped okra cooked with seafood and assorted meat for a full-bodied draw soup.',8,false,null,35,true,array[]::text[],24),
    ('soups-stews','ogbono','Ogbono','Ground wild mango seed soup, drawn thick and finished with assorted meat.',15,false,null,45,true,array[]::text[],25),
    ('soups-stews','goat-meat-stew','Goat Meat Stew','Tender goat meat braised down in our slow-fried tomato and pepper stew.',13,false,null,50,true,array[]::text[],26),
    ('soups-stews','turkey-stew','Turkey Stew','Soft turkey cuts simmered in a deep, well-seasoned pepper stew base.',13,false,null,50,true,array[]::text[],27),
    ('soups-stews','assorted-stew','Assorted Stew','Buka-style stew loaded with beef, tripe and cowfoot for full traditional flavour.',13,false,null,55,true,array['popular']::text[],28),
    ('soups-stews','plain-stew','Plain Stew','Our base tomato and pepper stew, slow-fried and ready to pair with any swallow.',5,false,null,30,true,array[]::text[],29),
    ('soups-stews','ewedu','Ewedu','Smooth jute leaf soup, traditionally whisked and served alongside stew.',5,false,null,25,true,array[]::text[],30),
    ('soups-stews','okra','Okra','Classic plain okra soup, freshly chopped and lightly seasoned.',5,false,null,25,true,array[]::text[],31),
    ('soups-stews','gbegiri','Gbegiri','Silky Yoruba bean soup — perfect in the classic abula trio with ewedu and stew.',7,false,null,40,true,array[]::text[],32),
    ('proteins','turkey-wings','Turkey Wings','Seasoned turkey wings, grilled and glazed in pepper sauce.',5,false,null,30,true,array['popular']::text[],33),
    ('proteins','stewed-turkey','Stewed Turkey','A single portion of turkey simmered in our house stew.',3,false,null,25,true,array[]::text[],34),
    ('proteins','assorted-meat','Assorted Meat','Beef, tripe and cowfoot cooked down soft in seasoned stock.',3,false,null,25,true,array[]::text[],35),
    ('proteins','stewed-beef','Stewed Beef','Tender beef cuts braised in our slow-fried pepper stew.',3,false,null,25,true,array[]::text[],36),
    ('proteins','stewed-chicken','Stewed Chicken','Bone-in chicken portion, seasoned and finished in rich tomato stew.',1.5,false,null,25,true,array['popular']::text[],37),
    ('proteins','chicken-drumstick','Chicken Drumstick','A single seasoned drumstick, grilled or stewed to your preference.',1.5,false,null,25,true,array[]::text[],38),
    ('proteins','chicken-wings','Chicken Wings','Peppered chicken wings, marinated overnight and grilled to order.',8,false,'5 pcs',30,true,array['new']::text[],39),
    ('proteins','fried-hake','Fried Hake','Seasoned hake fillet fried crisp — the everyday fish portion.',2,false,null,20,true,array[]::text[],40)
)
insert into public.products (
  category_id, slug, name, description, base_price, sale_price, price_on_request,
  portion_note, prep_time_minutes, status, is_available, tags, display_order
)
select c.id, seed.slug, seed.name, seed.description, seed.base_price, null,
  seed.price_on_request, seed.portion_note, seed.prep_time_minutes, 'active',
  seed.is_available, seed.tags, seed.display_order
from seed join public.categories c on c.slug = seed.category_slug
on conflict (slug) do update set
  category_id = excluded.category_id, name = excluded.name, description = excluded.description,
  base_price = excluded.base_price, sale_price = excluded.sale_price,
  price_on_request = excluded.price_on_request, portion_note = excluded.portion_note,
  prep_time_minutes = excluded.prep_time_minutes, status = excluded.status,
  is_available = excluded.is_available, tags = excluded.tags,
  display_order = excluded.display_order, updated_at = now();

with seed (slug, storage_path) as (
  values
    ('jollof-rice','/4474ba82-cf02-4264-9b7b-24159e623a2a.jpg'),
    ('fried-rice','/6d8eedd9-7301-4bae-bae7-8dfd65b5e422.jpg'),
    ('white-rice-designer-stew','/c018de98-a621-4496-8746-49148b87233d.jpg'),
    ('white-rice-ayamase','/e51c7a2f-77a9-4e6b-97f3-e36a2416af08.jpg'),
    ('ofada-rice-sauce','/e51c7a2f-77a9-4e6b-97f3-e36a2416af08.jpg'),
    ('coconut-rice','/6d8eedd9-7301-4bae-bae7-8dfd65b5e422.jpg'),
    ('half-and-half-rice','/b4ba3fb1-8dca-4476-b4d3-0b9ebf103f72.jpg'),
    ('plain-beans','/b33a0dbc-81a0-4162-8782-be77a3ba6083.jpg'),
    ('mashed-beans-palm-oil','/b33a0dbc-81a0-4162-8782-be77a3ba6083.jpg'),
    ('mixed-beans','/b33a0dbc-81a0-4162-8782-be77a3ba6083.jpg'),
    ('yam-porridge','/c2711a7e-a78f-4ece-a911-6c5c27eb2025.jpg'),
    ('yam-platter','/c2711a7e-a78f-4ece-a911-6c5c27eb2025.jpg'),
    ('yam-beans-sauce','/b33a0dbc-81a0-4162-8782-be77a3ba6083.jpg'),
    ('fish-platter','/9e735bad-c882-4df3-bb1c-55edf21bff1a.jpg'),
    ('meat-pie','/71d01a70-ea54-4ead-8187-1620a34332d1.jpg'),
    ('small-chops','/75fa0817-7bf0-434a-b4bb-a7eb7e2a6be4.jpg'),
    ('gizdodo','/12fe99e0-f232-411b-b31e-e7133ae0453a.jpg'),
    ('moinmoin','/cf86ec24-c463-4281-b1fe-eccac7bacc15.jpg'),
    ('plantain','/e3a1876a-f5cf-41b2-8fb3-976c373030b1.jpg'),
    ('akara','/d7d1ad74-18fb-4b6a-8718-4b28f9f7a22e.jpg'),
    ('goat-meat-pepper-soup','/9e735bad-c882-4df3-bb1c-55edf21bff1a.jpg'),
    ('tilapia-pepper-soup','/9e735bad-c882-4df3-bb1c-55edf21bff1a.jpg'),
    ('efo-riro','/c018de98-a621-4496-8746-49148b87233d.jpg'),
    ('egusi','/c285b655-e89e-4065-8353-7ce392924ea4.jpg'),
    ('mixed-okra','/c631bb12-26f6-424e-a0a5-d28b4fb259eb.jpg'),
    ('ogbono','/c631bb12-26f6-424e-a0a5-d28b4fb259eb.jpg'),
    ('goat-meat-stew','/c018de98-a621-4496-8746-49148b87233d.jpg'),
    ('turkey-stew','/22ef6220-c628-4e1f-ad02-676b6011ff84.jpg'),
    ('assorted-stew','/c018de98-a621-4496-8746-49148b87233d.jpg'),
    ('plain-stew','/c018de98-a621-4496-8746-49148b87233d.jpg'),
    ('ewedu','/c631bb12-26f6-424e-a0a5-d28b4fb259eb.jpg'),
    ('okra','/c631bb12-26f6-424e-a0a5-d28b4fb259eb.jpg'),
    ('gbegiri','/b33a0dbc-81a0-4162-8782-be77a3ba6083.jpg'),
    ('turkey-wings','/22ef6220-c628-4e1f-ad02-676b6011ff84.jpg'),
    ('stewed-turkey','/22ef6220-c628-4e1f-ad02-676b6011ff84.jpg'),
    ('assorted-meat','/53dcbb53-9766-4d49-a713-2b710263095f.jpg'),
    ('stewed-beef','/53dcbb53-9766-4d49-a713-2b710263095f.jpg'),
    ('stewed-chicken','/70f8147a-ca23-49df-aaed-d6fd230950ab.jpg'),
    ('chicken-drumstick','/70f8147a-ca23-49df-aaed-d6fd230950ab.jpg'),
    ('chicken-wings','/70f8147a-ca23-49df-aaed-d6fd230950ab.jpg'),
    ('fried-hake','/9e735bad-c882-4df3-bb1c-55edf21bff1a.jpg')
)
insert into public.product_images (product_id, storage_path, is_primary, display_order)
select p.id, seed.storage_path, true, 0
from seed join public.products p on p.slug = seed.slug
on conflict (product_id, storage_path) do update set
  is_primary = excluded.is_primary,
  display_order = excluded.display_order,
  updated_at = now();
