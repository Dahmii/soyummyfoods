import React, { useEffect, useState } from 'react';
import { Button } from '../../components/ui/button';
import { Field, Input } from '../../components/ui/input';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';
import { getAdminBusinessSettings, saveBusinessSettings } from '../../repositories/adminBusinessDeliveryRepository';
import { businessSettingsInputSchema, type BusinessSettingsInput } from '../../types/business';

const blank: BusinessSettingsInput = {
  business_name: '', legal_name: null, email: null, phone: null, whatsapp_number: null,
  address_line_1: null, address_line_2: null, city: null, postcode: null, country: null,
  currency_code: 'GBP', tax_enabled: false, tax_label: null, tax_rate_percent: null,
  tax_registration_number: null
};

function toNullable(value: string): string | null {
  return value.trim() || null;
}

export function AdminBusinessSettingsPage() {
  const { roles } = useAdminAuth();
  const canManage = roles.some((role) => role === 'owner' || role === 'manager');
  const [form, setForm] = useState<BusinessSettingsInput>(blank);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    void getAdminBusinessSettings().then((settings) => {
      setForm({
        business_name: settings.business_name, legal_name: settings.legal_name, email: settings.email,
        phone: settings.phone, whatsapp_number: settings.whatsapp_number, address_line_1: settings.address_line_1,
        address_line_2: settings.address_line_2, city: settings.city, postcode: settings.postcode,
        country: settings.country, currency_code: 'GBP', tax_enabled: settings.tax_enabled,
        tax_label: settings.tax_label, tax_rate_percent: settings.tax_rate_percent,
        tax_registration_number: settings.tax_registration_number
      });
      setLoaded(true);
    }).catch((cause: Error) => { setError(cause.message); setLoaded(true); });
  }, []);

  function setTaxEnabled(value: boolean) {
    setForm((current) => ({
      ...current,
      tax_enabled: value,
      tax_label: value ? current.tax_label : null,
      tax_rate_percent: value ? current.tax_rate_percent : null,
      tax_registration_number: value ? current.tax_registration_number : null
    }));
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError(null); setSaved(false);
    const parsed = businessSettingsInputSchema.safeParse(form);
    if (!parsed.success) { setError(parsed.error.issues[0]?.message ?? 'Check the business settings.'); return; }
    try { await saveBusinessSettings(parsed.data); setSaved(true); } catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not save business settings.'); }
  }

  if (!loaded) return <p>Loading business settings…</p>;
  const disabled = !canManage;
  return <section className="space-y-7"><div><p className="text-xs font-semibold uppercase tracking-[.16em] text-brand-500">Settings</p><h1 className="mt-2 font-display text-3xl font-bold">Business settings</h1>{disabled ? <p className="mt-2 text-sm text-ink/60">View only — staff cannot change business settings.</p> : null}</div>{error ? <p role="alert" className="text-sm text-red-700">{error}</p> : null}{saved ? <p className="text-sm text-emerald-700">Business settings saved.</p> : null}<form onSubmit={submit} className="grid gap-4 rounded-2xl border border-ink/10 bg-white p-5 sm:grid-cols-2"><Field label="Business name" htmlFor="business-name"><Input id="business-name" value={form.business_name} disabled={disabled} onChange={(event) => setForm({ ...form, business_name: event.target.value })} required /></Field><Field label="Legal name" htmlFor="business-legal-name"><Input id="business-legal-name" value={form.legal_name ?? ''} disabled={disabled} onChange={(event) => setForm({ ...form, legal_name: toNullable(event.target.value) })} /></Field><Field label="Email" htmlFor="business-email"><Input id="business-email" type="email" value={form.email ?? ''} disabled={disabled} onChange={(event) => setForm({ ...form, email: toNullable(event.target.value) })} /></Field><Field label="Phone" htmlFor="business-phone"><Input id="business-phone" value={form.phone ?? ''} disabled={disabled} onChange={(event) => setForm({ ...form, phone: toNullable(event.target.value) })} /></Field><Field label="WhatsApp number" htmlFor="business-whatsapp"><Input id="business-whatsapp" value={form.whatsapp_number ?? ''} disabled={disabled} onChange={(event) => setForm({ ...form, whatsapp_number: toNullable(event.target.value) })} /></Field><Field label="Country" htmlFor="business-country"><Input id="business-country" value={form.country ?? ''} disabled={disabled} onChange={(event) => setForm({ ...form, country: toNullable(event.target.value) })} /></Field><Field label="Address line 1" htmlFor="business-address-1" className="sm:col-span-2"><Input id="business-address-1" value={form.address_line_1 ?? ''} disabled={disabled} onChange={(event) => setForm({ ...form, address_line_1: toNullable(event.target.value) })} /></Field><Field label="Address line 2" htmlFor="business-address-2" className="sm:col-span-2"><Input id="business-address-2" value={form.address_line_2 ?? ''} disabled={disabled} onChange={(event) => setForm({ ...form, address_line_2: toNullable(event.target.value) })} /></Field><Field label="City" htmlFor="business-city"><Input id="business-city" value={form.city ?? ''} disabled={disabled} onChange={(event) => setForm({ ...form, city: toNullable(event.target.value) })} /></Field><Field label="Postcode" htmlFor="business-postcode"><Input id="business-postcode" value={form.postcode ?? ''} disabled={disabled} onChange={(event) => setForm({ ...form, postcode: toNullable(event.target.value) })} /></Field><Field label="Currency" htmlFor="business-currency"><Input id="business-currency" value="GBP" disabled /></Field><label className="flex items-end gap-2 pb-3 text-sm"><input type="checkbox" checked={form.tax_enabled} disabled={disabled} onChange={(event) => setTaxEnabled(event.target.checked)} /> Tax configured</label><Field label="Tax label" htmlFor="business-tax-label"><Input id="business-tax-label" value={form.tax_label ?? ''} disabled={disabled || !form.tax_enabled} onChange={(event) => setForm({ ...form, tax_label: toNullable(event.target.value) })} /></Field><Field label="Tax rate (%)" htmlFor="business-tax-rate"><Input id="business-tax-rate" type="number" min="0" max="100" step="0.01" value={form.tax_rate_percent ?? ''} disabled={disabled || !form.tax_enabled} onChange={(event) => setForm({ ...form, tax_rate_percent: event.target.value === '' ? null : Number(event.target.value) })} /></Field><Field label="Tax registration number" htmlFor="business-tax-registration"><Input id="business-tax-registration" value={form.tax_registration_number ?? ''} disabled={disabled || !form.tax_enabled} onChange={(event) => setForm({ ...form, tax_registration_number: toNullable(event.target.value) })} /></Field>{canManage ? <div className="sm:col-span-2"><Button type="submit">Save business settings</Button></div> : null}</form></section>;
}
