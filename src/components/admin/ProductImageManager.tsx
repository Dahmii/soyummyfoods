import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ImageIcon, UploadIcon } from 'lucide-react';
import { Button } from '../ui/button';
import { Field, Input } from '../ui/input';
import {
  listProductImages,
  removeProductImage,
  resolveProductImageUrl,
  saveProductImage,
  setPrimaryImage,
  uploadProductImage,
  validateProductImageFile
} from '../../repositories/adminCatalogRepository';
import { productImageInputSchema, type AdminProductImage } from '../../types/catalog';

interface ImageDraft {
  altText: string;
  displayOrder: number;
}

function ImagePreview({ image, alt }: { image: AdminProductImage; alt: string }) {
  const [failed, setFailed] = useState(false);
  const source = resolveProductImageUrl(image);

  useEffect(() => setFailed(false), [source]);

  if (failed) {
    return <div className="flex aspect-[4/3] items-center justify-center rounded-xl bg-cream-dark text-ink/45" role="img" aria-label="Image unavailable"><ImageIcon className="h-7 w-7" /></div>;
  }
  return <img src={source} alt={alt || 'Product image'} onError={() => setFailed(true)} className="aspect-[4/3] w-full rounded-xl bg-cream-dark object-cover" />;
}

export function ProductImageManager({ productId, productStatus }: { productId: string; productStatus: string }) {
  const [items, setItems] = useState<AdminProductImage[]>([]);
  const [drafts, setDrafts] = useState<Record<string, ImageDraft>>({});
  const [file, setFile] = useState<File | null>(null);
  const [localPreviewUrl, setLocalPreviewUrl] = useState<string | null>(null);
  const [altText, setAltText] = useState('');
  const [displayOrder, setDisplayOrder] = useState(0);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cleanupWarning, setCleanupWarning] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    try {
      const nextItems = await listProductImages(productId);
      setItems(nextItems);
      setDrafts(Object.fromEntries(nextItems.map((image) => [image.id, {
        altText: image.alt_text ?? '',
        displayOrder: image.display_order
      }])));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not load product images.');
    }
  }, [productId]);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    if (!file) {
      setLocalPreviewUrl(null);
      return;
    }
    const url = URL.createObjectURL(file);
    setLocalPreviewUrl(url);
    return () => URL.revokeObjectURL(url);
  }, [file]);

  function chooseFile(event: React.ChangeEvent<HTMLInputElement>) {
    const nextFile = event.target.files?.[0] ?? null;
    setError(null);
    if (!nextFile) {
      setFile(null);
      return;
    }
    try {
      validateProductImageFile(nextFile);
      setFile(nextFile);
    } catch (cause) {
      setFile(null);
      event.target.value = '';
      setError(cause instanceof Error ? cause.message : 'Could not use that image.');
    }
  }

  async function upload() {
    setError(null);
    setCleanupWarning(null);
    setUploading(true);
    try {
      await uploadProductImage(productId, file as File, {
        alt_text: altText.trim() || null,
        display_order: Number(displayOrder)
      });
      setFile(null);
      setAltText('');
      setDisplayOrder(0);
      if (inputRef.current) inputRef.current.value = '';
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not upload the image.');
    } finally {
      setUploading(false);
    }
  }

  async function saveDetails(image: AdminProductImage) {
    const draft = drafts[image.id];
    const parsed = productImageInputSchema.safeParse({
      storage_bucket: image.storage_bucket,
      storage_path: image.storage_path,
      alt_text: draft?.altText.trim() || null,
      display_order: Number(draft?.displayOrder)
    });
    if (!parsed.success) {
      setError(parsed.error.issues[0]?.message ?? 'Invalid image details.');
      return;
    }
    setError(null);
    try {
      await saveProductImage(productId, parsed.data, image.id);
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not save image details.');
    }
  }

  async function makePrimary(image: AdminProductImage) {
    setError(null);
    try {
      await setPrimaryImage(productId, image.id);
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not make this image primary.');
    }
  }

  async function remove(image: AdminProductImage) {
    setError(null);
    setCleanupWarning(null);
    try {
      const result = await removeProductImage(image);
      setCleanupWarning(result.cleanupWarning);
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not remove this image.');
    }
  }

  return <section className="space-y-5 rounded-2xl border border-ink/10 bg-white p-5">
    <div>
      <h2 className="font-display text-xl font-bold">Product images</h2>
      <p className="mt-1 text-sm text-ink/60">Upload JPEG, PNG, or WebP images up to 5 MiB. Existing local images remain available.</p>
    </div>
    {error ? <p role="alert" className="text-sm text-red-700">{error}</p> : null}
    {cleanupWarning ? <p role="status" className="text-sm text-amber-800">{cleanupWarning}</p> : null}

    {items.length === 0 ? <p className="rounded-xl border border-dashed border-ink/20 p-4 text-sm text-ink/60">No images yet. The first uploaded image becomes primary.</p> :
    <ul className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">{items.map((image) => {
      const draft = drafts[image.id] ?? { altText: image.alt_text ?? '', displayOrder: image.display_order };
      return <li key={image.id} className="space-y-3 rounded-xl border border-ink/10 p-3">
        <ImagePreview image={image} alt={draft.altText} />
        <div className="flex items-center justify-between gap-2 text-xs font-semibold uppercase tracking-[.1em] text-ink/60">
          <span>{image.storage_bucket === null ? 'Local image' : 'Uploaded image'}</span>
          {image.is_primary ? <span className="rounded-full bg-brand-100 px-2 py-1 text-brand-800">Primary</span> : null}
        </div>
        <Field label="Alt text" htmlFor={`image-alt-${image.id}`}>
          <Input id={`image-alt-${image.id}`} value={draft.altText} onChange={(event) => setDrafts((current) => ({ ...current, [image.id]: { ...draft, altText: event.target.value } }))} />
        </Field>
        <Field label="Display order" htmlFor={`image-order-${image.id}`}>
          <Input id={`image-order-${image.id}`} type="number" min="0" value={draft.displayOrder} onChange={(event) => setDrafts((current) => ({ ...current, [image.id]: { ...draft, displayOrder: Number(event.target.value) } }))} />
        </Field>
        <div className="flex flex-wrap gap-2">
          <Button type="button" size="sm" variant="outline" onClick={() => void saveDetails(image)}>Save details</Button>
          {!image.is_primary ? <Button type="button" size="sm" variant="outline" onClick={() => void makePrimary(image)}>Make primary</Button> : null}
          <Button type="button" size="sm" variant="ghost" disabled={productStatus === 'active' && image.is_primary} onClick={() => void remove(image)}>Remove</Button>
        </div>
      </li>;
    })}</ul>}

    <div className="space-y-4 rounded-xl border border-dashed border-ink/20 bg-cream/40 p-4">
      <div className="flex items-center gap-2"><UploadIcon className="h-4 w-4 text-brand-600" /><h3 className="font-semibold">Upload image</h3></div>
      <Field label="Choose image" htmlFor="product-image-upload">
        <Input ref={inputRef} id="product-image-upload" type="file" accept="image/jpeg,image/png,image/webp" onChange={chooseFile} disabled={uploading} />
      </Field>
      {file && localPreviewUrl ? <div className="grid gap-4 sm:grid-cols-[10rem_1fr]"><img src={localPreviewUrl} alt="Selected image preview" className="aspect-[4/3] w-full rounded-xl bg-cream-dark object-cover" /><div className="space-y-3"><p className="text-sm text-ink/60">{file.name} · {(file.size / 1024 / 1024).toFixed(2)} MiB</p><Field label="Alt text" htmlFor="new-image-alt"><Input id="new-image-alt" value={altText} onChange={(event) => setAltText(event.target.value)} disabled={uploading} /></Field><Field label="Display order" htmlFor="new-image-order"><Input id="new-image-order" type="number" min="0" value={displayOrder} onChange={(event) => setDisplayOrder(Number(event.target.value))} disabled={uploading} /></Field></div></div> : null}
      <Button type="button" disabled={!file || uploading} onClick={() => void upload()}>{uploading ? 'Uploading…' : 'Upload image'}</Button>
    </div>
  </section>;
}
