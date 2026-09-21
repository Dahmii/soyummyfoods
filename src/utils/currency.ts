export function formatCurrency(amount: number, currency: string): string {
  return new Intl.NumberFormat('en-GB', { style: 'currency', currency }).format(amount);
}

export function formatPrice(amount: number): string {
  return formatCurrency(amount, 'GBP');
}

export function formatMinorCurrency(amountMinor: number, currency: string): string {
  return formatCurrency(amountMinor / 100, currency);
}
