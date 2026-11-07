import { BadGatewayException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { Nutrients, nutrientsSchema } from './nutrition-schema';

type FdcFood = { fdcId?: number; description?: string; dataType?: string; foodNutrients?: { amount?: number; nutrient?: { id?: number; unitName?: string } }[] };
// The full details endpoint reports foodNutrients amounts per 100 g. Do not use labelNutrients (serving values).
export function mapUsdaFood(food: FdcFood) {
  const list = food.foodNutrients ?? [];
  const value = (ids: number[], unit: string) => {
    for (const id of ids) {
      const item = list.find(item => item.nutrient?.id === id && item.nutrient.unitName?.toLowerCase() === unit.toLowerCase());
      if (item && typeof item.amount === 'number' && Number.isFinite(item.amount) && item.amount >= 0) return item.amount;
    }
    return null;
  };
  const nutrients = { calories: value([1008, 2047, 2048], 'kcal'), protein: value([1003], 'g'), carbs: value([1005], 'g'), fat: value([1004], 'g'), fiber: value([1079], 'g'), sugar: value([2000, 1063], 'g'), sodium: value([1093], 'mg') };
  const parsed = nutrientsSchema.safeParse(nutrients);
  if (!parsed.success || typeof food.description !== 'string' || !food.description.trim() || !Number.isSafeInteger(food.fdcId)) throw new BadGatewayException('This food has incomplete or unsupported per-100-g data. Select another result or enter a food label.');
  return { name: food.description.trim().slice(0, 120), nutrients: parsed.data as Nutrients, source: { type: 'usda', label: 'USDA FoodData Central', fdcId: food.fdcId, dataType: food.dataType ?? 'Unknown', url: `https://fdc.nal.usda.gov/food-details/${food.fdcId}/nutrients`, retrievedAt: new Date().toISOString() } };
}
@Injectable()
export class NutritionProvider {
  get configured() { return Boolean(process.env.USDA_API_KEY?.trim()); }
  private async get(path: string, query: Record<string, string> = {}) {
    const key = process.env.USDA_API_KEY?.trim();
    if (!key) throw new ServiceUnavailableException('Food search is not connected yet. You can add values from a food label.');
    const url = new URL(`https://api.nal.usda.gov/fdc/v1/${path}`);
    url.searchParams.set('api_key', key);
    for (const [name, value] of Object.entries(query)) url.searchParams.set(name, value);
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(8000), redirect: 'error' });
      if (!response.ok) throw new Error('Provider unavailable');
      return await response.json();
    } catch { throw new BadGatewayException('Food search is temporarily unavailable. Your saved foods and logs are unaffected.'); }
  }
  async search(query: string) {
    const data = await this.get('foods/search', { query, pageSize: '12', dataType: 'Foundation,SR Legacy,Survey (FNDDS)' });
    if (!Array.isArray(data.foods)) throw new BadGatewayException('Food search returned an unreadable response.');
    return data.foods.filter((food: FdcFood) => Number.isSafeInteger(food.fdcId) && typeof food.description === 'string').map((food: FdcFood) => ({ fdcId: food.fdcId, name: food.description, dataType: food.dataType }));
  }
  async detail(id: number) {
    const food = await this.get(`food/${id}`, { format: 'full' });
    if (food.fdcId !== id) throw new BadGatewayException('Food search returned a different food reference.');
    // Restrict to food datasets with gram-based composition; branded serving/volume ambiguity is not imported here.
    if (!['Foundation', 'SR Legacy', 'Survey (FNDDS)'].includes(food.dataType)) throw new BadGatewayException('This food type is not supported for gram-based logging yet.');
    return mapUsdaFood(food);
  }
}
