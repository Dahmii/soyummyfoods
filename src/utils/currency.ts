const formatter = new Intl.NumberFormat('en-GB', {
  style: 'currency',
  currency: 'GBP'
});

export function formatPrice(amount: number): string {
  return formatter.format(amount);
}

export function formatMinorCurrency(amountMinor: number, currency: string): string {
  return new Intl.NumberFormat('en-GB', { style: 'currency', currency }).format(amountMinor / 100);
}
