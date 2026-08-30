export interface CateringRow {
  item: string;
  note?: string;
  halfTray: string;
  fullTray: string;
  cooler: string;
}

export const SOUP_BOWLS = [
'Efo-riro',
'Egusi',
'Assorted Meat (Buka) Stew',
'Ofada Stew / Sauce',
'Goat Meat Stew',
'Mixed Okra',
'Gbegiri',
'Ewedu'];


export const SOUP_BOWL_PRICE = '£20 each';

export const CATERING_RICE_AND_SIDES: CateringRow[] = [
{ item: 'Jollof Rice', halfTray: '£60', fullTray: '£80', cooler: '£140' },
{ item: 'Fried Rice', halfTray: '£70', fullTray: '£90', cooler: '£150' },
{
  item: 'Basmati White Rice',
  note: 'Rice alone',
  halfTray: '£30',
  fullTray: '£50',
  cooler: '£90'
},
{ item: 'Designer Stew', halfTray: '£150', fullTray: '£180', cooler: '£350' },
{ item: 'Ayamase / Ofada Sauce', halfTray: '£120', fullTray: '£190', cooler: '£360' },
{ item: 'Yam Porridge', halfTray: '£70', fullTray: '£120', cooler: '£220' },
{ item: 'Goatmeat Pepper Soup', halfTray: '£100', fullTray: '£180', cooler: '£350' },
{ item: 'Moinmoin', halfTray: '£30', fullTray: '£55', cooler: '£100' },
{
  item: 'Puff-Puff',
  halfTray: '£25',
  fullTray: '£45',
  cooler: '£80 (up to 200 pcs)'
},
{ item: 'Puff-Puff & Spring Rolls', halfTray: '£35', fullTray: '£65', cooler: '£125' },
{ item: 'Meat Pie', note: 'Per piece', halfTray: '£2 each', fullTray: '£2 each', cooler: '£2 each' },
{
  item: 'Akara',
  halfTray: '£30',
  fullTray: '£50 (up to 90 pcs)',
  cooler: '£90 (up to 180 pcs)'
},
{ item: 'Gizdodo', halfTray: '£70', fullTray: '£130', cooler: '£220' }];


export const CATERING_SOUPS_AND_PROTEINS: CateringRow[] = [
{ item: 'Efo-riro', halfTray: '£100 – £110', fullTray: '£190 – £200', cooler: '£370 – £375' },
{ item: 'Egusi', halfTray: '£100', fullTray: '£190', cooler: '£370' },
{ item: 'Mixed Okra', halfTray: '£100', fullTray: '£190', cooler: '£370' },
{ item: 'Assorted Meat Stew', halfTray: '£80', fullTray: '£150', cooler: '£300' },
{ item: 'Ogbono', halfTray: '£100', fullTray: '£180', cooler: '£350' },
{ item: 'Beef (Protein)', halfTray: '£150', fullTray: '£270', cooler: '£480' },
{ item: 'Stewed Chicken (Bone-in)', halfTray: '£60', fullTray: '£100', cooler: '£180' },
{ item: 'Stewed Chicken & Beef', halfTray: '£90', fullTray: '£170', cooler: '£280' },
{
  item: 'Stewed Assorted Meat',
  note: 'Beef, tripe & cowfoot',
  halfTray: '£100',
  fullTray: '£180',
  cooler: '£380'
},
{
  item: 'Stewed Turkey',
  note: 'Min. 10 pcs',
  halfTray: '£3 each',
  fullTray: '£3 each',
  cooler: '£3 each'
},
{
  item: 'Grilled Turkey Wings',
  note: 'Priced per piece',
  halfTray: '£4 each',
  fullTray: '£4 each',
  cooler: '£4 each'
},
{ item: 'Grilled / Fried Chicken', halfTray: '£70', fullTray: '£130', cooler: '£210' },
{ item: 'Grilled Chicken Drumsticks', halfTray: '£70', fullTray: '£110', cooler: '£200' },
{ item: 'Stewed Hake Fish', halfTray: '£95', fullTray: '£180', cooler: '£340' }];