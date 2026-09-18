import {
  menuResponseSchema,
  type MenuCatalog,
  type MenuCategoryOption,
  type MenuItem } from
'../types/menu';
import { isSupabaseConfigured } from '../lib/supabase';
import { fetchMenuFromSupabase } from '../repositories/menuRepository';

const IMAGES = {
  jollof: "/4474ba82-cf02-4264-9b7b-24159e623a2a.jpg",

  friedrice: "/6d8eedd9-7301-4bae-bae7-8dfd65b5e422.jpg",

  ofada: "/e51c7a2f-77a9-4e6b-97f3-e36a2416af08.jpg",

  beans: "/b33a0dbc-81a0-4162-8782-be77a3ba6083.jpg",

  yamporridge: "/c2711a7e-a78f-4ece-a911-6c5c27eb2025.jpg",

  meatpie: "/71d01a70-ea54-4ead-8187-1620a34332d1.jpg",

  smallchops: "/75fa0817-7bf0-434a-b4bb-a7eb7e2a6be4.jpg",

  gizdodo: "/12fe99e0-f232-411b-b31e-e7133ae0453a.jpg",

  akara: "/d7d1ad74-18fb-4b6a-8718-4b28f9f7a22e.jpg",

  moimoi: "/cf86ec24-c463-4281-b1fe-eccac7bacc15.jpg",

  plantain: "/e3a1876a-f5cf-41b2-8fb3-976c373030b1.jpg",

  peppersoup: "/9e735bad-c882-4df3-bb1c-55edf21bff1a.jpg",

  efori: "/c018de98-a621-4496-8746-49148b87233d.jpg",

  egusi: "/c285b655-e89e-4065-8353-7ce392924ea4.jpg",

  okra: "/c631bb12-26f6-424e-a0a5-d28b4fb259eb.jpg",
  chicken: "/70f8147a-ca23-49df-aaed-d6fd230950ab.jpg",

  turkeywings: "/22ef6220-c628-4e1f-ad02-676b6011ff84.jpg",

  suya: "/53dcbb53-9766-4d49-a713-2b710263095f.jpg",
  puffpuff: "/f5ef9e16-7090-43d8-b041-7d6fc624abb0.jpg",

  hero: "/b4ba3fb1-8dca-4476-b4d3-0b9ebf103f72.jpg"
} as const;

const RAW_MENU: unknown[] = [
/* ── Rice Dishes ─────────────────────────────────────────── */
{
  id: 'jollof-rice',
  name: 'Jollof Rice',
  description:
  'Our signature smoky party jollof, slow-simmered in rich tomato, pepper and traditional spices.',
  price: 9,
  image: IMAGES.jollof,
  category: 'rice-dishes',
  prepTimeMinutes: 35,
  available: true,
  tags: ['popular'],
  rating: 4.9
},
{
  id: 'fried-rice',
  name: 'Fried Rice',
  description:
  'Buttery long-grain rice tossed with garden vegetables, sweetcorn and seasoned stock.',
  price: 10,
  image: IMAGES.friedrice,
  category: 'rice-dishes',
  prepTimeMinutes: 35,
  available: true,
  tags: ['popular'],
  rating: 4.8
},
{
  id: 'white-rice-designer-stew',
  name: 'White Rice & Designer Stew',
  description:
  'Fluffy steamed rice served with our slow-fried designer pepper stew.',
  price: 12,
  image: IMAGES.efori,
  category: 'rice-dishes',
  prepTimeMinutes: 40,
  available: true,
  tags: [],
  rating: 4.7
},
{
  id: 'white-rice-ayamase',
  name: 'White Rice & Ayamase Stew',
  description:
  'Steamed rice with authentic ayamase — green pepper sauce cooked down in bleached palm oil.',
  price: 15,
  image: IMAGES.ofada,
  category: 'rice-dishes',
  prepTimeMinutes: 45,
  available: true,
  tags: ['popular'],
  rating: 4.9
},
{
  id: 'ofada-rice-sauce',
  name: 'Ofada Rice & Sauce',
  description:
  'Locally milled ofada rice wrapped in banana leaf, served with rich ayamase sauce and assorted meat.',
  price: 15,
  image: IMAGES.ofada,
  category: 'rice-dishes',
  prepTimeMinutes: 45,
  available: true,
  tags: ['special'],
  rating: 4.9
},
{
  id: 'coconut-rice',
  name: 'Coconut Rice',
  description:
  'Fragrant rice simmered in fresh coconut milk. Priced to portion — message the kitchen for a quote.',
  price: null,
  image: IMAGES.friedrice,
  category: 'rice-dishes',
  prepTimeMinutes: 40,
  available: true,
  tags: [],
  rating: 4.7,
  priceOnRequest: true
},
{
  id: 'half-and-half-rice',
  name: 'Half & Half (Jollof & Fried)',
  description:
  'Can’t choose? A split portion of our smoky jollof and party fried rice in one pack.',
  price: 10,
  image: IMAGES.hero,
  category: 'rice-dishes',
  prepTimeMinutes: 35,
  available: true,
  tags: ['popular'],
  rating: 4.8
},

/* ── Beans Dishes ────────────────────────────────────────── */
{
  id: 'plain-beans',
  name: 'Plain Beans',
  description: 'Honey beans cooked soft and seasoned simply — a comforting everyday staple.',
  price: 5,
  image: IMAGES.beans,
  category: 'beans-dishes',
  prepTimeMinutes: 40,
  available: true,
  tags: [],
  rating: 4.5
},
{
  id: 'mashed-beans-palm-oil',
  name: 'Mashed Beans & Palm Oil Base',
  description:
  'Beans mashed down and finished in a rich palm oil and pepper base with smoked fish.',
  price: 12,
  image: IMAGES.beans,
  category: 'beans-dishes',
  prepTimeMinutes: 45,
  available: true,
  tags: ['popular'],
  rating: 4.7
},
{
  id: 'mixed-beans',
  name: 'Mixed Beans',
  description: 'Beans cooked with plantain and peppers for a fuller, sweeter plate.',
  price: 10,
  image: IMAGES.beans,
  category: 'beans-dishes',
  prepTimeMinutes: 45,
  available: true,
  tags: [],
  rating: 4.6
},

/* ── Yam Dishes ──────────────────────────────────────────── */
{
  id: 'yam-porridge',
  name: 'Yam Porridge',
  description:
  'Asaro — soft yam simmered down in palm oil, peppers and leafy greens until creamy.',
  price: 12,
  image: IMAGES.yamporridge,
  category: 'yam-dishes',
  prepTimeMinutes: 45,
  available: true,
  tags: ['popular'],
  rating: 4.8
},
{
  id: 'yam-platter',
  name: 'Yam Platter',
  description:
  'A generous platter of fried and boiled yam served with egg sauce and pepper stew.',
  price: 19,
  image: IMAGES.yamporridge,
  category: 'yam-dishes',
  prepTimeMinutes: 45,
  available: true,
  tags: [],
  rating: 4.7
},
{
  id: 'yam-beans-sauce',
  name: 'Yam & Beans with Sauce',
  description: 'The classic pairing of yam and honey beans, finished with rich pepper sauce.',
  price: 18,
  image: IMAGES.beans,
  category: 'yam-dishes',
  prepTimeMinutes: 50,
  available: true,
  tags: [],
  rating: 4.6
},
{
  id: 'fish-platter',
  name: 'Fish Platter',
  description:
  'Whole seasoned fish with fried yam or plantain and our house pepper sauce. Our biggest sharing plate.',
  price: 25,
  image: IMAGES.peppersoup,
  category: 'yam-dishes',
  prepTimeMinutes: 55,
  available: true,
  tags: ['special'],
  rating: 4.9
},

/* ── Starters & Sides ────────────────────────────────────── */
{
  id: 'meat-pie',
  name: 'Meat Pie',
  description: 'Buttery hand-crimped pastry filled with seasoned minced beef, potato and carrot.',
  price: 2.5,
  image: IMAGES.meatpie,
  category: 'starters-sides',
  prepTimeMinutes: 15,
  available: true,
  tags: ['popular'],
  rating: 4.8
},
{
  id: 'small-chops',
  name: 'Small Chops',
  description: 'Party pack of spring rolls and puff puff, fried fresh to order.',
  price: 5,
  image: IMAGES.smallchops,
  category: 'starters-sides',
  prepTimeMinutes: 20,
  available: true,
  tags: ['popular'],
  rating: 4.8,
  portion: 'Spring rolls & puff'
},
{
  id: 'gizdodo',
  name: 'Gizdodo',
  description: 'Diced gizzard and sweet plantain tossed in a glossy bell pepper sauce.',
  price: 8,
  image: IMAGES.gizdodo,
  category: 'starters-sides',
  prepTimeMinutes: 25,
  available: true,
  tags: ['new'],
  rating: 4.8
},
{
  id: 'moinmoin',
  name: 'Moinmoin',
  description: 'Steamed bean pudding with peppers and onion, wrapped and cooked traditionally.',
  price: 2.5,
  image: IMAGES.moimoi,
  category: 'starters-sides',
  prepTimeMinutes: 40,
  available: true,
  tags: [],
  rating: 4.7
},
{
  id: 'plantain',
  name: 'Plantain',
  description: 'Ripe plantain fried until the edges caramelise — dodo done properly.',
  price: 3,
  image: IMAGES.plantain,
  category: 'starters-sides',
  prepTimeMinutes: 12,
  available: true,
  tags: ['popular'],
  rating: 4.9
},
{
  id: 'akara',
  name: 'Akara',
  description: 'Peeled bean fritters fried golden and crisp, light and fluffy inside.',
  price: 5,
  image: IMAGES.akara,
  category: 'starters-sides',
  prepTimeMinutes: 20,
  available: true,
  tags: ['new'],
  rating: 4.6,
  portion: '5 pcs'
},

/* ── Pepper Soups ────────────────────────────────────────── */
{
  id: 'goat-meat-pepper-soup',
  name: 'Goat Meat Pepper Soup',
  description:
  'Fiery, aromatic broth of tender goat meat with uziza, scent leaf and pepper soup spices.',
  price: 12,
  image: IMAGES.peppersoup,
  category: 'pepper-soups',
  prepTimeMinutes: 50,
  available: true,
  tags: ['popular'],
  rating: 4.9
},
{
  id: 'tilapia-pepper-soup',
  name: 'Tilapia Pepper Soup',
  description: 'Fresh tilapia poached in a light, peppery broth with herbs and scent leaf.',
  price: 12,
  image: IMAGES.peppersoup,
  category: 'pepper-soups',
  prepTimeMinutes: 35,
  available: true,
  tags: ['new'],
  rating: 4.8
},

/* ── Soups & Stews ───────────────────────────────────────── */
{
  id: 'efo-riro',
  name: 'Efo-riro',
  description:
  'Rich spinach stew simmered in palm oil with assorted meat, locust beans and peppers.',
  price: 13,
  image: IMAGES.efori,
  category: 'soups-stews',
  prepTimeMinutes: 45,
  available: true,
  tags: ['popular'],
  rating: 4.9
},
{
  id: 'egusi',
  name: 'Egusi',
  description: 'Ground melon seeds cooked with spinach, palm oil and assorted meats.',
  price: 13,
  image: IMAGES.egusi,
  category: 'soups-stews',
  prepTimeMinutes: 45,
  available: true,
  tags: ['popular'],
  rating: 4.9
},
{
  id: 'mixed-okra',
  name: 'Mixed Okra',
  description: 'Chopped okra cooked with seafood and assorted meat for a full-bodied draw soup.',
  price: 8,
  image: IMAGES.okra,
  category: 'soups-stews',
  prepTimeMinutes: 35,
  available: true,
  tags: [],
  rating: 4.7
},
{
  id: 'ogbono',
  name: 'Ogbono',
  description: 'Ground wild mango seed soup, drawn thick and finished with assorted meat.',
  price: 15,
  image: IMAGES.okra,
  category: 'soups-stews',
  prepTimeMinutes: 45,
  available: true,
  tags: [],
  rating: 4.8
},
{
  id: 'goat-meat-stew',
  name: 'Goat Meat Stew',
  description: 'Tender goat meat braised down in our slow-fried tomato and pepper stew.',
  price: 13,
  image: IMAGES.efori,
  category: 'soups-stews',
  prepTimeMinutes: 50,
  available: true,
  tags: [],
  rating: 4.8
},
{
  id: 'turkey-stew',
  name: 'Turkey Stew',
  description: 'Soft turkey cuts simmered in a deep, well-seasoned pepper stew base.',
  price: 13,
  image: IMAGES.turkeywings,
  category: 'soups-stews',
  prepTimeMinutes: 50,
  available: true,
  tags: [],
  rating: 4.7
},
{
  id: 'assorted-stew',
  name: 'Assorted Stew',
  description: 'Buka-style stew loaded with beef, tripe and cowfoot for full traditional flavour.',
  price: 13,
  image: IMAGES.efori,
  category: 'soups-stews',
  prepTimeMinutes: 55,
  available: true,
  tags: ['popular'],
  rating: 4.8
},
{
  id: 'plain-stew',
  name: 'Plain Stew',
  description: 'Our base tomato and pepper stew, slow-fried and ready to pair with any swallow.',
  price: 5,
  image: IMAGES.efori,
  category: 'soups-stews',
  prepTimeMinutes: 30,
  available: true,
  tags: [],
  rating: 4.6
},
{
  id: 'ewedu',
  name: 'Ewedu',
  description: 'Smooth jute leaf soup, traditionally whisked and served alongside stew.',
  price: 5,
  image: IMAGES.okra,
  category: 'soups-stews',
  prepTimeMinutes: 25,
  available: true,
  tags: [],
  rating: 4.6
},
{
  id: 'okra',
  name: 'Okra',
  description: 'Classic plain okra soup, freshly chopped and lightly seasoned.',
  price: 5,
  image: IMAGES.okra,
  category: 'soups-stews',
  prepTimeMinutes: 25,
  available: true,
  tags: [],
  rating: 4.5
},
{
  id: 'gbegiri',
  name: 'Gbegiri',
  description: 'Silky Yoruba bean soup — perfect in the classic abula trio with ewedu and stew.',
  price: 7,
  image: IMAGES.beans,
  category: 'soups-stews',
  prepTimeMinutes: 40,
  available: true,
  tags: [],
  rating: 4.7
},

/* ── Proteins ────────────────────────────────────────────── */
{
  id: 'turkey-wings',
  name: 'Turkey Wings',
  description: 'Seasoned turkey wings, grilled and glazed in pepper sauce.',
  price: 5,
  image: IMAGES.turkeywings,
  category: 'proteins',
  prepTimeMinutes: 30,
  available: true,
  tags: ['popular'],
  rating: 4.8
},
{
  id: 'stewed-turkey',
  name: 'Stewed Turkey',
  description: 'A single portion of turkey simmered in our house stew.',
  price: 3,
  image: IMAGES.turkeywings,
  category: 'proteins',
  prepTimeMinutes: 25,
  available: true,
  tags: [],
  rating: 4.6
},
{
  id: 'assorted-meat',
  name: 'Assorted Meat',
  description: 'Beef, tripe and cowfoot cooked down soft in seasoned stock.',
  price: 3,
  image: IMAGES.suya,
  category: 'proteins',
  prepTimeMinutes: 25,
  available: true,
  tags: [],
  rating: 4.6
},
{
  id: 'stewed-beef',
  name: 'Stewed Beef',
  description: 'Tender beef cuts braised in our slow-fried pepper stew.',
  price: 3,
  image: IMAGES.suya,
  category: 'proteins',
  prepTimeMinutes: 25,
  available: true,
  tags: [],
  rating: 4.7
},
{
  id: 'stewed-chicken',
  name: 'Stewed Chicken',
  description: 'Bone-in chicken portion, seasoned and finished in rich tomato stew.',
  price: 1.5,
  image: IMAGES.chicken,
  category: 'proteins',
  prepTimeMinutes: 25,
  available: true,
  tags: ['popular'],
  rating: 4.7
},
{
  id: 'chicken-drumstick',
  name: 'Chicken Drumstick',
  description: 'A single seasoned drumstick, grilled or stewed to your preference.',
  price: 1.5,
  image: IMAGES.chicken,
  category: 'proteins',
  prepTimeMinutes: 25,
  available: true,
  tags: [],
  rating: 4.6
},
{
  id: 'chicken-wings',
  name: 'Chicken Wings',
  description: 'Peppered chicken wings, marinated overnight and grilled to order.',
  price: 8,
  image: IMAGES.chicken,
  category: 'proteins',
  prepTimeMinutes: 30,
  available: true,
  tags: ['new'],
  rating: 4.8,
  portion: '5 pcs'
},
{
  id: 'fried-hake',
  name: 'Fried Hake',
  description: 'Seasoned hake fillet fried crisp — the everyday fish portion.',
  price: 2,
  image: IMAGES.peppersoup,
  category: 'proteins',
  prepTimeMinutes: 20,
  available: true,
  tags: [],
  rating: 4.5
}];


/** Validated at module load so malformed menu data fails loudly and early. */
export const MENU_ITEMS: MenuItem[] = menuResponseSchema.parse(RAW_MENU);

/** Presentation-only metadata retained until ratings are explicitly modelled. */
export const MENU_ITEM_RATINGS: Readonly<Record<string, number>> = Object.fromEntries(
  MENU_ITEMS.flatMap((item) => item.rating === null || item.rating === undefined ? [] : [[item.id, item.rating]])
);

const LEGACY_MENU_CATEGORIES: MenuCategoryOption[] = [
  { slug: 'rice-dishes', name: 'Rice Dishes', displayOrder: 0 },
  { slug: 'beans-dishes', name: 'Beans Dishes', displayOrder: 1 },
  { slug: 'yam-dishes', name: 'Yam Dishes', displayOrder: 2 },
  { slug: 'starters-sides', name: 'Starters & Sides', displayOrder: 3 },
  { slug: 'pepper-soups', name: 'Pepper Soups', displayOrder: 4 },
  { slug: 'soups-stews', name: 'Soups & Stews', displayOrder: 5 },
  { slug: 'proteins', name: 'Proteins', displayOrder: 6 }
];

/** Simulates an async menu fetch so the UI can exercise loading and error states. */
export function fetchMenu(signal?: AbortSignal): Promise<MenuCatalog> {
  if (isSupabaseConfigured()) {
    return fetchMenuFromSupabase(signal, MENU_ITEM_RATINGS);
  }

  return new Promise((resolve, reject) => {
    const timer = window.setTimeout(() => {
      const parsed = menuResponseSchema.safeParse(RAW_MENU);
      if (!parsed.success) {
        reject(new Error('The menu could not be loaded right now.'));
        return;
      }
      // Static entries have no authoritative product IDs or inventory state.
      // They remain browseable for local development but cannot enter checkout.
      resolve({ items: parsed.data.map((item) => ({ ...item, available: false })), categories: LEGACY_MENU_CATEGORIES });
    }, 650);

    signal?.addEventListener('abort', () => {
      window.clearTimeout(timer);
      reject(new DOMException('Aborted', 'AbortError'));
    });
  });
}
