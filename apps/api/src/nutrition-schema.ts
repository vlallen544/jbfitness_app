import { z } from 'zod';
import { BadRequestException } from '@nestjs/common';
import { isoDay, todayInIndia } from './workout-schema';

export const nutrientKeys = ['calories', 'protein', 'carbs', 'fat', 'fiber', 'sugar', 'sodium'] as const;
export type Nutrients = Record<typeof nutrientKeys[number], number | null>;
const grams = z.number().min(0).max(100);
export const nutrientsSchema = z.object({
  calories: z.number().min(0).max(1000), protein: grams, carbs: grams, fat: grams,
  fiber: grams.nullable().default(null), sugar: grams.nullable().default(null), sodium: z.number().min(0).max(100000).nullable().default(null),
}).strict();
export const targetSchema = z.object({
  calories: z.number().min(1).max(10000), protein: z.number().min(0).max(1000), carbs: z.number().min(0).max(2000), fat: z.number().min(0).max(1000),
  fiber: z.number().min(0).max(200).nullable().default(null), sugar: z.number().min(0).max(1000).nullable().default(null), sodium: z.number().min(0).max(100000).nullable().default(null),
}).strict();
export const mealSchema = z.enum(['breakfast', 'lunch', 'dinner', 'snack']);
export const portionSchema = z.number().gt(0).max(10000).refine(value => Math.abs(value * 100 - Math.round(value * 100)) < 0.000001, 'Use up to two decimal places.');
export const foodSchema = z.object({ name: z.string().trim().min(1).max(120), sourceNote: z.string().trim().min(1).max(300), nutrients: nutrientsSchema, requestId: z.uuid() }).strict();
export const entrySchema = z.object({ foodId: z.uuid(), date: isoDay, meal: mealSchema, grams: portionSchema, requestId: z.uuid() }).strict();
export const editSchema = z.object({ grams: portionSchema, meal: mealSchema, revision: z.number().int().min(1), deleted: z.boolean().default(false), requestId: z.uuid() }).strict();
export const targetsSaveSchema = z.object({ date: isoDay, nutrients: targetSchema, revision: z.number().int().min(0), requestId: z.uuid() }).strict();
export function nutritionParse<T>(schema: z.ZodType<T>, input: unknown): T {
  const result = schema.safeParse(input);
  if (!result.success) throw new BadRequestException('Check food values, grams, meal, date and save reference. Required nutrients must be provided; leave unknown optional nutrients blank.');
  return result.data;
}
export function nutritionDate(input: unknown = todayInIndia()) {
  const day = nutritionParse(isoDay, input);
  if (day < '2020-01-01' || day > todayInIndia()) throw new BadRequestException('Choose a date from 2020 through today.');
  return day;
}
export function scaleNutrients(nutrients: Nutrients, grams: number): Nutrients {
  return Object.fromEntries(nutrientKeys.map(key => [key, nutrients[key] === null ? null : nutrients[key]! * grams / 100])) as Nutrients;
}
export function nutritionTotals(entries: { nutrients: Nutrients }[]) {
  return Object.fromEntries(nutrientKeys.map(key => {
    const missingEntries = entries.filter(entry => entry.nutrients[key] === null).length;
    const known = Math.round(entries.reduce((sum, entry) => sum + (entry.nutrients[key] ?? 0), 0) * 100) / 100;
    return [key, { known, complete: missingEntries === 0, missingEntries }];
  }));
}
