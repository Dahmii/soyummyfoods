export const IMAGERY = {
  hero: "/b4ba3fb1-8dca-4476-b4d3-0b9ebf103f72.jpg",
  chef: "/1ff23ab8-1c44-4868-b055-54ce889269f7.jpg",
  kitchenTeam: "/ab35cf6b-e058-4a8b-9b26-10b78e484f0d.jpg",

  spices: "/6e768e1f-69c7-404a-94c1-a2669446d421.jpg",

  jollof: "/4474ba82-cf02-4264-9b7b-24159e623a2a.jpg",

  egusi: "/c285b655-e89e-4065-8353-7ce392924ea4.jpg",

  suya: "/53dcbb53-9766-4d49-a713-2b710263095f.jpg",
  puffpuff: "/f5ef9e16-7090-43d8-b041-7d6fc624abb0.jpg",

  peppersoup: "/9e735bad-c882-4df3-bb1c-55edf21bff1a.jpg",

  moimoi: "/cf86ec24-c463-4281-b1fe-eccac7bacc15.jpg",

  plantain: "/e3a1876a-f5cf-41b2-8fb3-976c373030b1.jpg",

  chicken: "/70f8147a-ca23-49df-aaed-d6fd230950ab.jpg",

  zobo: "/a5ab6272-c0ed-40d3-8589-6dfe0d5105c9.jpg"
} as const;

export interface GalleryEntry {
  title: string;
  caption: string;
  image: string;
}

export const GALLERY: GalleryEntry[] = [
{
  title: 'Yaji Prep',
  caption: 'Hand-blending our premium peanut suya rub before every grill service.',
  image: IMAGERY.spices
},
{
  title: 'Celebration Feast',
  caption: 'A beautifully styled table of West African classics for a London wedding.',
  image: IMAGERY.hero
},
{
  title: 'Smoky Party Jollof',
  caption: 'Wood-smoke swirling over the party pot — the flavour everyone remembers.',
  image: IMAGERY.jollof
},
{
  title: 'Kitchen Craft',
  caption: 'Our Southwark kitchen team plating for a 200-cover catering order.',
  image: IMAGERY.kitchenTeam
},
{
  title: 'Egusi Textures',
  caption: 'A close-up of fresh egusi soup with spinach and assorted meats.',
  image: IMAGERY.egusi
},
{
  title: 'Food Styling',
  caption: 'Behind the lens of our moi moi shoot, wrapped fresh in banana leaf.',
  image: IMAGERY.moimoi
},
{
  title: 'Fresh Puff Puff',
  caption: 'Golden, pillowy and dusted the moment they leave the fryer.',
  image: IMAGERY.puffpuff
},
{
  title: 'Fire & Spice',
  caption: 'Obe ata simmering down slowly for our peppered chicken glaze.',
  image: IMAGERY.chicken
}];


export interface VideoFeature {
  title: string;
  description: string;
  duration: string;
  views: string;
  image: string;
}

export const VIDEOS: VideoFeature[] = [
{
  title: 'Mastering Jollof: The Authentic Recipe',
  description:
  'Go behind the scenes as our head chef shows you how to achieve the perfect smoky flavour at home.',
  duration: '12:45',
  views: '24k views',
  image: IMAGERY.jollof
},
{
  title: 'Behind The Kitchen: Crafting True Heritage',
  description:
  'Discover our roots, our mission, and our passion for bringing West African food culture to the UK.',
  duration: '08:20',
  views: '15k views',
  image: IMAGERY.kitchenTeam
}];


export interface BlogPost {
  title: string;
  excerpt: string;
  category: string;
  date: string;
  readTime: string;
  image: string;
}

export const FEATURED_POST: BlogPost = {
  title: 'The History of Jollof Rice: A West African Classic',
  excerpt:
  'Trace the fascinating evolution of West Africa\u2019s legendary rice dish, from its origins with the ancient Jollof Empire in Senegal to the passionate culinary competitions that define West African food culture today.',
  category: 'Food History',
  date: 'May 18, 2026',
  readTime: '8 min read',
  image: IMAGERY.chicken
};

export const POSTS: BlogPost[] = [
{
  title: 'The Deep Royal Roots of Egusi',
  excerpt: 'A journey through Yoruba food history and the royal celebrations that gave it birth.',
  category: 'Food History',
  date: 'May 12, 2026',
  readTime: '6 min read',
  image: IMAGERY.egusi
},
{
  title: 'How to Correctly Pound Yam',
  excerpt: 'An essential guide to selecting dry yams and mastering that smooth, elastic texture.',
  category: 'Cooking Tips',
  date: 'May 08, 2026',
  readTime: '5 min read',
  image: IMAGERY.moimoi
},
{
  title: 'What Makes Party Jollof Different',
  excerpt: 'Deconstructing the chemistry of firewood cooking, cast iron pots and slow steam.',
  category: 'Culture',
  date: 'Apr 29, 2026',
  readTime: '7 min read',
  image: IMAGERY.peppersoup
},
{
  title: 'Catering Nigerian Weddings in the UK',
  excerpt: 'Tips on planning fusion West African wedding menus that delight diverse crowds.',
  category: 'Events',
  date: 'Apr 15, 2026',
  readTime: '4 min read',
  image: IMAGERY.hero
},
{
  title: 'Suya Yaji: The Spice Blend Explained',
  excerpt: 'The story behind ground ginger, roasted peanuts and red pepper flakes.',
  category: 'Ingredients',
  date: 'Apr 04, 2026',
  readTime: '6 min read',
  image: IMAGERY.spices
},
{
  title: 'Healthy Eating with Native Greens',
  excerpt: 'How native spinach, waterleaf and bitterleaf provide powerful trace nutrients.',
  category: 'Nutrition',
  date: 'Mar 22, 2026',
  readTime: '5 min read',
  image: IMAGERY.plantain
}];


export const BLOG_CATEGORIES = [
{ label: 'Food History', count: 12 },
{ label: 'Cooking Tips', count: 18 },
{ label: 'West African Culture', count: 9 },
{ label: 'Event Catering', count: 7 },
{ label: 'Ingredient Spotlights', count: 11 },
{ label: 'Nutrition Guides', count: 6 }];