import { menuResponseSchema, type MenuItem } from '../types/menu';

const IMAGES = {
  jollof: "/4474ba82-cf02-4264-9b7b-24159e623a2a.jpg",

  egusi: "/c285b655-e89e-4065-8353-7ce392924ea4.jpg",

  suya: "/53dcbb53-9766-4d49-a713-2b710263095f.jpg",
  puffpuff: "/f5ef9e16-7090-43d8-b041-7d6fc624abb0.jpg",

  moimoi: "/cf86ec24-c463-4281-b1fe-eccac7bacc15.jpg",

  peppersoup: "/9e735bad-c882-4df3-bb1c-55edf21bff1a.jpg",

  friedrice: "/6d8eedd9-7301-4bae-bae7-8dfd65b5e422.jpg",

  plantain: "/e3a1876a-f5cf-41b2-8fb3-976c373030b1.jpg",

  chicken: "/70f8147a-ca23-49df-aaed-d6fd230950ab.jpg",

  chinchin: "/19c30c4b-08d7-4045-b6a0-42e1c63361bf.jpg",

  zobo: "/a5ab6272-c0ed-40d3-8589-6dfe0d5105c9.jpg"
} as const;

const RAW_MENU: unknown[] = [
{
  id: 'smoky-party-jollof',
  name: 'Smoky Party Jollof Rice',
  description:
  'The legendary Nigerian party jollof. Slow-simmered basmati infused with rich tomato, bell pepper and scotch bonnet.',
  price: 14.5,
  image: IMAGES.jollof,
  category: 'rice-dishes',
  prepTimeMinutes: 35,
  available: true,
  tags: ['popular'],
  rating: 4.9
},
{
  id: 'egusi-pounded-yam',
  name: 'Egusi Soup with Pounded Yam',
  description:
  'Richly textured ground melon seeds cooked with spinach, palm oil, locust beans and assorted meats.',
  price: 16.0,
  image: IMAGES.egusi,
  category: 'soups-stews',
  prepTimeMinutes: 45,
  available: true,
  tags: ['popular'],
  rating: 4.8
},
{
  id: 'flame-grilled-suya',
  name: 'Flame-Grilled Beef Suya',
  description:
  'Tender 24h-marinated beef cuts, dry-rubbed with our peanut yaji spice and grilled over live fire.',
  price: 12.5,
  image: IMAGES.suya,
  category: 'grilled-fried',
  prepTimeMinutes: 25,
  available: true,
  tags: ['popular', 'special'],
  rating: 4.9,
  specialPrice: 10.5
},
{
  id: 'golden-puff-puff',
  name: 'Golden Sweet Puff Puff',
  description:
  'Our crowd-favourite sweet yeast dough, fried to pillowy perfection and dusted with fine sugar.',
  price: 6.5,
  image: IMAGES.puffpuff,
  category: 'sides-snacks',
  prepTimeMinutes: 15,
  available: true,
  tags: ['popular'],
  rating: 4.7
},
{
  id: 'banana-leaf-moi-moi',
  name: 'Banana Leaf Moi Moi',
  description:
  'Steamed honey bean pudding wrapped in banana leaves with boiled egg, peppers and smoked fish.',
  price: 9.0,
  image: IMAGES.moimoi,
  category: 'sides-snacks',
  prepTimeMinutes: 40,
  available: true,
  tags: ['new'],
  rating: 4.6
},
{
  id: 'goat-pepper-soup',
  name: 'Goat Meat Pepper Soup',
  description:
  'A fiery, aromatic broth of tender goat meat, uziza, scent leaf and traditional pepper soup spices.',
  price: 13.75,
  image: IMAGES.peppersoup,
  category: 'soups-stews',
  prepTimeMinutes: 50,
  available: true,
  tags: ['new'],
  rating: 4.8
},
{
  id: 'party-fried-rice',
  name: 'Nigerian Party Fried Rice',
  description:
  'Buttery long-grain rice tossed with liver, sweetcorn, garden vegetables and king prawns.',
  price: 14.0,
  image: IMAGES.friedrice,
  category: 'rice-dishes',
  prepTimeMinutes: 35,
  available: true,
  tags: [],
  rating: 4.7
},
{
  id: 'sweet-dodo',
  name: 'Caramelised Sweet Dodo',
  description:
  'Ripe plantain fried until the edges caramelise — the perfect sweet counterpoint to any main.',
  price: 5.0,
  image: IMAGES.plantain,
  category: 'sides-snacks',
  prepTimeMinutes: 12,
  available: true,
  tags: ['special'],
  rating: 4.8,
  specialPrice: 3.75
},
{
  id: 'peppered-chicken',
  name: 'Obe Ata Peppered Chicken',
  description:
  'Grilled chicken quarters glazed in our slow-fried obe ata pepper sauce with sweet onion rings.',
  price: 15.25,
  image: IMAGES.chicken,
  category: 'grilled-fried',
  prepTimeMinutes: 40,
  available: false,
  tags: ['popular'],
  rating: 4.9
},
{
  id: 'crunchy-chin-chin',
  name: 'Crunchy Nutmeg Chin Chin',
  description:
  'Hand-cut cubes of nutmeg-scented dough fried golden — our best-loved everyday crunch.',
  price: 4.5,
  image: IMAGES.chinchin,
  category: 'desserts',
  prepTimeMinutes: 10,
  available: true,
  tags: ['new'],
  rating: 4.5
},
{
  id: 'chilled-zobo',
  name: 'Chilled Ginger Zobo',
  description:
  'Deep-red hibiscus infusion brewed with pineapple, ginger and cloves. Served ice cold.',
  price: 3.95,
  image: IMAGES.zobo,
  category: 'drinks',
  prepTimeMinutes: 5,
  available: true,
  tags: ['new', 'special'],
  rating: 4.6,
  specialPrice: 2.95
},
{
  id: 'family-jollof-tray',
  name: 'Family Jollof Feast Tray',
  description:
  'A full catering tray of party jollof with grilled chicken and dodo. Feeds six to eight guests.',
  price: 48.0,
  image: IMAGES.jollof,
  category: 'rice-dishes',
  prepTimeMinutes: 75,
  available: true,
  tags: ['special'],
  rating: 5,
  specialPrice: 42.0
}];


/** Validated at module load so malformed menu data fails loudly and early. */
export const MENU_ITEMS: MenuItem[] = menuResponseSchema.parse(RAW_MENU);

/** Simulates an async menu fetch so the UI can exercise loading and error states. */
export function fetchMenu(signal?: AbortSignal): Promise<MenuItem[]> {
  return new Promise((resolve, reject) => {
    const timer = window.setTimeout(() => {
      const parsed = menuResponseSchema.safeParse(RAW_MENU);
      if (!parsed.success) {
        reject(new Error('The menu could not be loaded right now.'));
        return;
      }
      resolve(parsed.data);
    }, 650);

    signal?.addEventListener('abort', () => {
      window.clearTimeout(timer);
      reject(new DOMException('Aborted', 'AbortError'));
    });
  });
}