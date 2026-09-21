import { formatCurrency, formatPrice } from './currency';
import type { CartLine } from '../hooks/useCartStore';

/** Business WhatsApp number in international format, digits only. */
export const WHATSAPP_NUMBER = '447311809250';
export const WHATSAPP_DISPLAY = '+44 73 1180 9250';

function toUrl(message: string): string {
  return `https://wa.me/${WHATSAPP_NUMBER}?text=${encodeURIComponent(message)}`;
}

export function openWhatsApp(message: string): void {
  window.open(toUrl(message), '_blank', 'noopener,noreferrer');
}

interface OrderMessageInput {
  lines: CartLine[];
  subtotal: number;
  delivery: number;
  total: number;
  customer?: {
    fullName: string;
    phone: string;
    postcode: string;
    address: string;
    notes?: string;
  };
}

export function buildOrderMessage({
  lines,
  subtotal,
  delivery,
  total,
  customer
}: OrderMessageInput): string {
  const rows = lines.map(
    (line) =>
    `• ${line.quantity} × ${line.name} — ${formatPrice(line.unitPrice * line.quantity)}`
  );

  const parts = [
  'Hello SoYummy Foods! I would like to place this order:',
  '',
  ...rows,
  '',
  `Subtotal: ${formatPrice(subtotal)}`,
  `Delivery: ${delivery === 0 ? 'Free' : formatPrice(delivery)}`,
  `Total: ${formatPrice(total)}`];


  if (customer) {
    parts.push(
      '',
      '— My details —',
      `Name: ${customer.fullName}`,
      `Phone: ${customer.phone}`,
      `Address: ${customer.address}, ${customer.postcode}`
    );
    if (customer.notes) parts.push(`Notes: ${customer.notes}`);
  }

  parts.push(
    '',
    'Please confirm availability, payment details and my delivery slot. Thank you!'
  );

  return parts.join('\n');
}

interface ConfirmedOrderMessageInput {
  orderNumber: string;
  items?: Array<{ name: string; quantity: number }>;
  subtotal: number;
  deliveryFee: number;
  discountAmount: number;
  taxAmount: number;
  total: number;
  currency: string;
}

export function buildConfirmedOrderMessage({
  orderNumber,
  items,
  subtotal,
  deliveryFee,
  discountAmount,
  taxAmount,
  total,
  currency
}: ConfirmedOrderMessageInput): string {
  const parts = [
    'Hi SoYummy 👋',
    '',
    "I've just placed and paid for an order.",
    '',
    `Order: ${orderNumber}`
  ];
  if (items?.length) {
    parts.push('', 'Items:', ...items.map((item) => `${item.quantity} × ${item.name}`));
  }
  parts.push(
    '',
    `Subtotal: ${formatCurrency(subtotal, currency)}`,
    `Delivery: ${formatCurrency(deliveryFee, currency)}`
  );
  if (discountAmount !== 0) parts.push(`Discount: −${formatCurrency(discountAmount, currency)}`);
  if (taxAmount !== 0) parts.push(`Tax: ${formatCurrency(taxAmount, currency)}`);
  parts.push(`Total: ${formatCurrency(total, currency)}`, '', "Please confirm you've received it.");
  return parts.join('\n');
}

export function buildItemEnquiryMessage(itemName: string): string {
  return `Hello SoYummy Foods! Please could you quote me a price for ${itemName}?`;
}

export function buildPaymentHelpMessage(orderNumber: string): string {
  return `Hi, I've just placed order ${orderNumber} on the So Yummy Foods website. I'd like the payment details please.`;
}

export function buildCateringEnquiryMessage(itemName?: string): string {
  return itemName ?
  `Hello SoYummy Foods! I'd like to place a bulk catering order for ${itemName}. Please could you confirm tray sizes, availability and payment details?` :
  "Hello SoYummy Foods! I'd like to discuss a bulk catering order. Please could you help with tray sizes, pricing and availability?";
}

export function buildAllergyEnquiryMessage(): string {
  return 'Hello SoYummy Foods! I have a severe allergy and would like to discuss my dietary requirements before ordering.';
}
