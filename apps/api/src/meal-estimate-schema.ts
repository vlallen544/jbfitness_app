import { BadGatewayException } from '@nestjs/common';
import { z } from 'zod';
import { nutrientsSchema, mealSchema, portionSchema } from './nutrition-schema';
import { isoDay } from './workout-schema';

export const estimateRequestSchema = z.object({ requestId: z.uuid(), description: z.string().trim().max(1500).default('') }).strict();
const modelNutrients = z.object({ calories: z.number(), protein: z.number(), carbs: z.number(), fat: z.number(), fiber: z.number().nullable(), sugar: z.number().nullable(), sodium: z.number().nullable() }).strict();
export const modelMealSchema = z.object({
  status: z.enum(['estimated', 'unclear']),
  clarification: z.string().nullable(),
  uncertainty: z.enum(['low', 'medium', 'high']),
  assumptions: z.array(z.string()),
  items: z.array(z.object({ name: z.string(), grams: z.number(), nutrients: modelNutrients }).strict()),
}).strict();
export const reviewItemSchema = z.object({ name: z.string().trim().min(1).max(120), grams: portionSchema, nutrients: nutrientsSchema }).strict();
export const reviewSaveSchema = z.object({ requestId: z.uuid(), date: isoDay, meal: mealSchema, items: z.array(reviewItemSchema).min(1).max(8) }).strict();
export function validateMealDraft(value: unknown) {
  const parsed = modelMealSchema.safeParse(value);
  if (!parsed.success) throw new BadGatewayException('The AI response could not be validated. Try a clearer photo or description.');
  const draft = parsed.data;
  if (draft.assumptions.length > 6 || draft.assumptions.some(text => !text.trim() || text.length > 250) || (draft.clarification?.length ?? 0) > 500) throw new BadGatewayException('The estimate contained unsupported details. Please try again.');
  if (draft.status === 'unclear') {
    if (draft.items.length !== 0 || !draft.clarification?.trim()) throw new BadGatewayException('The AI could not produce a usable estimate.');
    return draft;
  }
  const items = z.array(reviewItemSchema).min(1).max(8).safeParse(draft.items);
  if (!items.success || items.data.reduce((sum, item) => sum + item.grams, 0) > 10000) throw new BadGatewayException('The estimated portions or nutrients were outside supported limits. Please try again.');
  return { ...draft, items: items.data };
}
