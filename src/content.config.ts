import { defineCollection, z } from 'astro:content';

const kapitelSchema = z.object({
  title: z.string(),
  date: z.string().optional(),
  draft: z.boolean().optional(),
  authors: z.array(z.string()).optional(),
  band: z.string().optional()
});

export const collections = {
  // generische Kapitel-Collection (für die meisten Dateien)
  kapitel: defineCollection({ schema: kapitelSchema }),

  // einzelne Kapitelnummern (optional; du kannst auch nur "kapitel" verwenden)
  'kapitel-01': defineCollection({ schema: kapitelSchema }),
  'kapitel-02': defineCollection({ schema: kapitelSchema }),
  // ...falls du diese spezifischen Collections brauchst, füge sie hinzu

  // Vorwort / Schlussdialog / Titelblätter / Anhang
  vorwort: defineCollection({ schema: z.object({ title: z.string().optional(), draft: z.boolean().optional() }) }),
  schlussdialog: defineCollection({ schema: z.object({ title: z.string().optional(), draft: z.boolean().optional() }) }),
  titelblatt: defineCollection({ schema: z.object({ title: z.string().optional() }) }),
  quellenverzeichnis: defineCollection({ schema: z.object({ title: z.string().optional() }) }),

  // Band-spezifische Collections (falls du die Ordner so verwendest)
  'band1-titelblatt': defineCollection({ schema: z.object({ title: z.string().optional() }) }),
  'band1-inhaltsverzeichnis': defineCollection({ schema: z.object({ title: z.string().optional() }) }),
  'band1-anhang': defineCollection({ schema: z.object({ title: z.string().optional() }) }),
  'band2-titelblatt': defineCollection({ schema: z.object({ title: z.string().optional() }) }),
  'band2-inhaltsverzeichnis': defineCollection({ schema: z.object({ title: z.string().optional() }) }),
  'band2-anhang': defineCollection({ schema: z.object({ title: z.string().optional() }) }),
  'band3-titelblatt': defineCollection({ schema: z.object({ title: z.string().optional() }) }),
  'band3-inhaltsverzeichnis': defineCollection({ schema: z.object({ title: z.string().optional() }) }),
  'band3-anhang': defineCollection({ schema: z.object({ title: z.string().optional() }) }),

  // gesamtwerk collection (falls du meta für das Gesamtwerk brauchst)
  gesamtwerk: defineCollection({ schema: z.object({ title: z.string().optional() }) })
};
export default collections;