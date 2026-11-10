import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {dashboardFixture} from './support/staff-dashboard';

test('supplement catalogue, owner inventory and saved customer carts',async t=>{
  const f=await dashboardFixture({startDashboard:false});
  const request=async(path:string,token?:string,method='GET',body?:unknown)=>{const response=await fetch(`${f.apiBase}${path}`,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});return{status:response.status,data:await response.json()};};
  const product=(overrides:Record<string,unknown>={})=>({sku:`JB-${randomUUID().slice(0,8).toUpperCase()}`,name:'Labelled protein powder',brand:'Test brand',category:'protein',description:'Technical test product description.',ingredients:'Ingredients from the test label.',allergenNotes:'Contains milk.',packSize:'1 kg',servingSize:'30 g',imageUrl:null,pricePaise:129950,stock:5,status:'draft',revision:0,requestId:randomUUID(),...overrides});
  const id=randomUUID(),draftId=randomUUID();let published=product({status:'published'});
  const save=(productId:string,body:unknown)=>request(`/staff/store/products/${productId}`,f.admin.token,'PUT',body);
  try{
    const other=await f.auth.register({email:`cart-${randomUUID()}@example.test`,password:'Cart-test-password-42!',displayName:'Unpaid customer'});
    await t.test('store is customer-readable without a paid plan; only the owner manages products',async()=>{
      assert.equal((await request('/store/products')).status,401);
      assert.equal((await request('/store/products',f.trainer.token)).status,403);
      assert.equal((await request('/store/products',other.token)).status,200);
      assert.equal((await request('/staff/store/products',f.customer.token)).status,403);
      assert.equal((await request(`/staff/store/products/${id}`,f.trainer.token,'PUT',published)).status,403);
      assert.equal((await request(`/staff/store/products/${id}`,f.customer.token,'PUT',published)).status,403);
      assert.equal((await save(id,{...published,pricePaise:-1})).status,400);
      assert.equal((await save(id,{...published,stock:0.5})).status,400);
      assert.equal((await save(id,{...published,imageUrl:'not-a-url'})).status,400);
      assert.equal((await save(id,{...published,imageUrl:'http://res.cloudinary.com/demo/image/upload/a.jpg'})).status,400);
      assert.equal((await save(id,{...published,imageUrl:'https://res.cloudinary.com.evil.example/a.jpg'})).status,400);
      assert.equal((await save(id,{...published,imageUrl:'https://user:password@res.cloudinary.com/a.jpg'})).status,400);
    });
    await t.test('product saves deduplicate, reject stale edits and keep drafts private',async()=>{
      const [a,b]=await Promise.all([save(id,published),save(id,published)]);assert.equal(a.status,200);assert.deepEqual(a.data,b.data);assert.equal(a.data.revision,1);
      assert.equal((await save(id,{...published,name:'Changed payload'})).status,409);
      assert.equal((await save(id,{...published,requestId:randomUUID()})).status,409);
      assert.equal((await save(draftId,product())).status,200);
      assert.equal((await request(`/store/products/${draftId}`,other.token)).status,404);
      assert.equal((await request('/store/products',other.token)).data.products.length,1);
      assert.equal((await request('/staff/store/products',f.admin.token)).data.products.length,2);
      const detail=(await request(`/store/products/${id}`,other.token)).data;assert.equal(detail.product.ingredients,published.ingredients);assert.equal(detail.checkoutEnabled,false);assert.equal(detail.currency,'INR');
      assert.equal((await request('/store/products?category=unknown',other.token)).status,400);
      assert.equal((await request('/store/products?offset=-1',other.token)).status,400);
      assert.equal((await request('/store/products?customerId=other',other.token)).status,400);
    });
    await t.test('saved cart uses owner scope, server prices and duplicate-safe revisioned writes',async()=>{
      assert.equal((await request('/me/cart',f.trainer.token)).status,403);
      const body={quantity:2,revision:0,requestId:randomUUID()},path=`/me/cart/${id}`;
      assert.equal((await request(path,f.customer.token,'PUT',{...body,pricePaise:1})).status,400);
      assert.equal((await request(path,f.customer.token,'PUT',{...body,quantity:6})).status,409);
      const [a,b]=await Promise.all([request(path,f.customer.token,'PUT',body),request(path,f.customer.token,'PUT',body)]);assert.equal(a.status,200);assert.deepEqual(a.data,b.data);assert.equal(a.data.revision,1);
      assert.equal((await request(path,f.customer.token,'PUT',{...body,quantity:1})).status,409);
      assert.equal((await request(path,f.customer.token,'PUT',{...body,requestId:randomUUID()})).status,409);
      const cart=(await request('/me/cart',f.customer.token)).data;assert.equal(cart.itemCount,2);assert.equal(cart.subtotalPaise,259900);assert.equal(cart.items[0].quantity,2);assert.equal(cart.checkoutEnabled,false);
      assert.equal((await request('/me/cart',other.token)).data.items.length,0);
      assert.equal((await request(`/me/cart/${draftId}`,other.token,'PUT',{...body,quantity:1})).status,404);
      assert.equal((await request(path,other.token,'PUT',{...body,quantity:11})).status,400);
      const stock=(await request(`/store/products/${id}`,other.token)).data.product.stock;assert.equal(stock,5);
    });
    await t.test('cart refresh reflects price/stock changes, archives and removal without placing an order',async()=>{
      published={...published,pricePaise:99999,stock:1,revision:1,requestId:randomUUID()};assert.equal((await save(id,published)).status,200);
      let cart=(await request('/me/cart',f.customer.token)).data;assert.equal(cart.subtotalPaise,199998);assert.equal(cart.hasUnavailableItems,true);
      assert.equal((await request(`/me/cart/${id}`,f.customer.token,'PUT',{quantity:1,revision:1,requestId:randomUUID()})).status,200);
      cart=(await request('/me/cart',f.customer.token)).data;assert.equal(cart.subtotalPaise,99999);assert.equal(cart.hasUnavailableItems,false);
      assert.equal((await save(id,{...published,status:'archived',revision:2,requestId:randomUUID()})).status,200);
      assert.equal((await request(`/store/products/${id}`,f.customer.token)).status,404);
      assert.equal((await request('/me/cart',f.customer.token)).data.items[0].available,false);
      assert.equal((await request(`/me/cart/${id}`,f.customer.token,'PUT',{quantity:0,revision:2,requestId:randomUUID()})).status,200);
      assert.equal((await request('/me/cart',f.customer.token)).data.items.length,0);
      assert.equal((await request('/store/orders',f.customer.token,'POST',{})).status,404);
    });
    await t.test('catalogue search and pagination are bounded; unpaid users can save carts with a 20-product cap',async()=>{
      const ids:string[]=[];
      for(let i=0;i<21;i++){const productId=randomUUID();ids.push(productId);assert.equal((await save(productId,product({name:`Bulk fixture ${String(i).padStart(2,'0')}`,status:'published'}))).status,200);}
      const first=(await request('/store/products?q=Bulk',other.token)).data;assert.equal(first.products.length,20);assert.equal(first.nextOffset,20);
      const next=(await request('/store/products?q=Bulk&offset=20',other.token)).data;assert.equal(next.products.length,1);assert.equal(next.nextOffset,null);assert.ok(!first.products.some((p:any)=>p.id===next.products[0].id));
      assert.equal((await request('/store/products?q=%25',other.token)).data.products.length,0);
      assert.equal((await request('/store/products?category=creatine',other.token)).data.products.length,0);
      for(let i=0;i<20;i++)assert.equal((await request(`/me/cart/${ids[i]}`,other.token,'PUT',{quantity:1,revision:i,requestId:randomUUID()})).status,200);
      assert.equal((await request(`/me/cart/${ids[20]}`,other.token,'PUT',{quantity:1,revision:20,requestId:randomUUID()})).status,400);
      assert.equal((await request('/me/cart',other.token)).data.items.length,20);
      const tables=(await f.db.pool.query("SELECT relrowsecurity FROM pg_class WHERE oid=ANY(ARRAY['store_products'::regclass,'store_carts'::regclass,'store_cart_items'::regclass,'store_changes'::regclass])")).rows;assert.equal(tables.length,4);assert.ok(tables.every(row=>row.relrowsecurity));
    });
  }finally{await f.cleanup();}
});
