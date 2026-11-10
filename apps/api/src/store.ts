import {BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Inject, Injectable, NotFoundException, Param, Put, Query, Req, UseGuards} from '@nestjs/common';
import {createHash,randomUUID} from 'node:crypto';
import {z} from 'zod';
import type {PoolClient} from 'pg';
import {AuthGuard,User} from './auth';
import {Database} from './database';
import {customerOnly} from './workouts';

const categories=['protein','creatine','vitamins','other'] as const;
const productSchema=z.object({
  sku:z.string().trim().regex(/^[A-Z0-9_-]{3,40}$/),name:z.string().trim().min(1).max(100),brand:z.string().trim().min(1).max(80),category:z.enum(categories),
  description:z.string().trim().min(1).max(3000),ingredients:z.string().trim().min(1).max(2000),allergenNotes:z.string().trim().max(1000),packSize:z.string().trim().min(1).max(100),servingSize:z.string().trim().max(100),
  imageUrl:z.string().max(2048).url().refine(value=>{try{const url=new URL(value);return url.protocol==='https:'&&url.hostname==='res.cloudinary.com'&&!url.username&&!url.password&&!url.port;}catch{return false;}}).nullable(),
  pricePaise:z.number().int().min(1).max(10000000),stock:z.number().int().min(0).max(1000000),status:z.enum(['draft','published','archived']),revision:z.number().int().min(0),requestId:z.uuid(),
}).strict();
const querySchema=z.object({q:z.string().trim().max(100).default(''),category:z.enum(categories).optional(),offset:z.coerce.number().int().min(0).max(10000).default(0)}).strict();
const cartSchema=z.object({quantity:z.number().int().min(0).max(10),revision:z.number().int().min(0),requestId:z.uuid()}).strict();
const orderRequestSchema=z.object({cartRevision:z.number().int().min(0),requestId:z.uuid(),confirmed:z.literal(true)}).strict();
const orderStatusSchema=z.object({revision:z.number().int().min(1),requestId:z.uuid(),status:z.enum(['reviewed','closed'])}).strict();
function parse<T>(schema:z.ZodType<T>,input:unknown):T{const result=schema.safeParse(input);if(!result.success)throw new BadRequestException('Check the product fields, quantity, revision and request reference.');return result.data;}
function admin(user:User){if(user.role!=='admin')throw new ForbiddenException('Only the owner can manage store products.');}
const productColumns=`id,sku,name,brand,category,description,ingredients,allergen_notes AS "allergenNotes",pack_size AS "packSize",serving_size AS "servingSize",image_url AS "imageUrl",price_paise AS "pricePaise",stock,status,revision`;
const digest=(value:unknown)=>createHash('sha256').update(JSON.stringify(value)).digest('hex');

@Injectable()
export class StoreService {
  constructor(@Inject(Database)private readonly db:Database){}
  async catalogue(user:User,input:unknown,owner=false){
    if(owner)admin(user);else customerOnly(user);
    const query=parse(querySchema,input);
    const search=`%${query.q.replace(/[\\%_]/g,'\\$&')}%`;
    const rows=(await this.db.pool.query(`SELECT ${productColumns} FROM store_products WHERE ($1::boolean OR status='published') AND ($2::text IS NULL OR category=$2) AND (name ILIKE $3 OR brand ILIKE $3 OR sku ILIKE $3) ORDER BY name,id LIMIT 21 OFFSET $4`,[owner,query.category??null,search,query.offset])).rows;
    return{products:rows.slice(0,20),nextOffset:rows.length>20&&query.offset+20<=10000?query.offset+20:null,categories,currency:'INR',checkoutEnabled:false};
  }
  async detail(user:User,value:string){
    customerOnly(user);const id=parse(z.uuid(),value);
    const product=(await this.db.pool.query(`SELECT ${productColumns} FROM store_products WHERE id=$1 AND status='published'`,[id])).rows[0];
    if(!product)throw new NotFoundException('Product is unavailable.');
    return{product,currency:'INR',checkoutEnabled:false};
  }
  private async replay(c:PoolClient,user:User,requestId:string,hash:string){
    const old=(await c.query('SELECT payload_hash,result FROM store_changes WHERE actor_id=$1 AND request_id=$2',[user.id,requestId])).rows[0];
    if(old&&old.payload_hash!==hash)throw new ConflictException('This request reference was used for a different store change.');return old?.result;
  }
  private async record(c:PoolClient,user:User,requestId:string,hash:string,result:unknown){
    await c.query('INSERT INTO store_changes(actor_id,request_id,payload_hash,result) VALUES($1,$2,$3,$4)',[user.id,requestId,hash,JSON.stringify(result)]);
  }
  async saveProduct(user:User,value:string,input:unknown){
    admin(user);const id=parse(z.uuid(),value),body=parse(productSchema,input),hash=digest({kind:'product',id,...body}),c=await this.db.pool.connect();
    try{
      await c.query('BEGIN');
      // Serialize this actor's retry references across products and creators of the same product ID.
      await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,14014))',[user.id]);
      await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,14015))',[id]);
      if(!(await c.query("SELECT id FROM users WHERE id=$1 AND role='admin' FOR SHARE",[user.id])).rowCount)throw new ForbiddenException('Owner access changed.');
      const replay=await this.replay(c,user,body.requestId,hash);if(replay){await c.query('COMMIT');return replay;}
      const old=(await c.query('SELECT revision FROM store_products WHERE id=$1 FOR UPDATE',[id])).rows[0];
      if((old?.revision??0)!==body.revision)throw new ConflictException('This product changed. Reload the catalogue before editing.');
      const revision=body.revision+1;
      await c.query(`INSERT INTO store_products(id,sku,name,brand,category,description,ingredients,allergen_notes,pack_size,serving_size,image_url,price_paise,stock,status,revision)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
        ON CONFLICT(id) DO UPDATE SET sku=excluded.sku,name=excluded.name,brand=excluded.brand,category=excluded.category,description=excluded.description,ingredients=excluded.ingredients,allergen_notes=excluded.allergen_notes,pack_size=excluded.pack_size,serving_size=excluded.serving_size,image_url=excluded.image_url,price_paise=excluded.price_paise,stock=excluded.stock,status=excluded.status,revision=excluded.revision,updated_at=now()`,
        [id,body.sku,body.name,body.brand,body.category,body.description,body.ingredients,body.allergenNotes,body.packSize,body.servingSize,body.imageUrl,body.pricePaise,body.stock,body.status,revision]);
      const result={id,revision};await this.record(c,user,body.requestId,hash,result);await c.query('COMMIT');return result;
    }catch(e){await c.query('ROLLBACK');if((e as {code?:string}).code==='23505')throw new ConflictException('This SKU or request reference is already in use.');throw e;}finally{c.release();}
  }
  async cart(user:User){
    customerOnly(user);const c=await this.db.pool.connect();
    try{
      await c.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const revision=(await c.query('SELECT revision FROM store_carts WHERE customer_id=$1',[user.id])).rows[0]?.revision??0;
      const items=(await c.query(`SELECT p.id,p.name,p.brand,p.pack_size AS "packSize",p.image_url AS "imageUrl",p.price_paise AS "pricePaise",p.stock,p.status,i.quantity FROM store_cart_items i JOIN store_products p ON p.id=i.product_id WHERE i.customer_id=$1 ORDER BY p.name,p.id`,[user.id])).rows.map(p=>({...p,available:p.status==='published'&&p.stock>=p.quantity,lineTotalPaise:p.pricePaise*p.quantity}));
      await c.query('COMMIT');
      return{revision,items,itemCount:items.reduce((sum,p)=>sum+p.quantity,0),subtotalPaise:items.reduce((sum,p)=>sum+p.lineTotalPaise,0),currency:'INR',checkoutEnabled:false,hasUnavailableItems:items.some(p=>!p.available)};
    }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
  }
  async setQuantity(user:User,value:string,input:unknown){
    customerOnly(user);const id=parse(z.uuid(),value),body=parse(cartSchema,input),hash=digest({kind:'cart',id,...body}),c=await this.db.pool.connect();
    try{
      await c.query('BEGIN');
      if(!(await c.query("SELECT id FROM users WHERE id=$1 AND role='customer' FOR UPDATE",[user.id])).rowCount)throw new ForbiddenException('Customer access changed.');
      const replay=await this.replay(c,user,body.requestId,hash);if(replay){await c.query('COMMIT');return replay;}
      await c.query('INSERT INTO store_carts(customer_id) VALUES($1) ON CONFLICT DO NOTHING',[user.id]);
      const current=(await c.query('SELECT revision FROM store_carts WHERE customer_id=$1 FOR UPDATE',[user.id])).rows[0];
      if(current.revision!==body.revision)throw new ConflictException('Your cart changed on another screen or device. Reload it before editing.');
      if(body.quantity===0){await c.query('DELETE FROM store_cart_items WHERE customer_id=$1 AND product_id=$2',[user.id,id]);}
      else{
        const product=(await c.query("SELECT stock FROM store_products WHERE id=$1 AND status='published' FOR SHARE",[id])).rows[0];
        if(!product)throw new NotFoundException('Product is unavailable.');
        if(product.stock<body.quantity)throw new ConflictException('That quantity is no longer in stock. Refresh the product or cart.');
        const count=(await c.query('SELECT count(*)::int AS n FROM store_cart_items WHERE customer_id=$1 AND product_id<>$2',[user.id,id])).rows[0].n;
        if(count>=20)throw new BadRequestException('Keep up to 20 different products in your cart.');
        await c.query('INSERT INTO store_cart_items(customer_id,product_id,quantity) VALUES($1,$2,$3) ON CONFLICT(customer_id,product_id) DO UPDATE SET quantity=excluded.quantity',[user.id,id,body.quantity]);
      }
      const revision=body.revision+1;await c.query('UPDATE store_carts SET revision=$2 WHERE customer_id=$1',[user.id,revision]);
      const result={saved:true,revision};await this.record(c,user,body.requestId,hash,result);await c.query('COMMIT');return result;
    }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
  }
  async customerOrders(user:User){
    customerOnly(user);
    const rows=(await this.db.pool.query(`SELECT id,status,line_items AS "lineItems",subtotal_paise AS "subtotalPaise",revision,created_at AS "createdAt",updated_at AS "updatedAt" FROM store_order_requests WHERE customer_id=$1 ORDER BY created_at DESC,id LIMIT 100`,[user.id])).rows;
    return{orders:rows,currency:'INR',paymentEnabled:false,deliveryEnabled:false};
  }
  async requestOrder(user:User,input:unknown){
    customerOnly(user);const body=parse(orderRequestSchema,input),c=await this.db.pool.connect();
    try{
      await c.query('BEGIN');
      await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,15015))',[user.id]);
      if(!(await c.query("SELECT id FROM users WHERE id=$1 AND role='customer' FOR UPDATE",[user.id])).rowCount)throw new ForbiddenException('Customer access changed.');
      const prior=(await c.query('SELECT id FROM store_order_requests WHERE customer_id=$1 AND request_id=$2',[user.id,body.requestId])).rows[0];
      if(prior){await c.query('COMMIT');return{id:prior.id,status:'requested',duplicate:true};}
      const cart=(await c.query('SELECT revision FROM store_carts WHERE customer_id=$1 FOR UPDATE',[user.id])).rows[0];
      if(!cart)throw new BadRequestException('Add at least one product before requesting an order.');
      if(cart.revision!==body.cartRevision)throw new ConflictException('Your cart changed. Refresh it before requesting an order.');
      const items=(await c.query(`SELECT p.id,p.sku,p.name,p.brand,p.pack_size AS "packSize",p.price_paise AS "pricePaise",p.stock,p.status,i.quantity FROM store_cart_items i JOIN store_products p ON p.id=i.product_id WHERE i.customer_id=$1 ORDER BY p.id FOR SHARE OF p`,[user.id])).rows;
      if(!items.length)throw new BadRequestException('Add at least one product before requesting an order.');
      if(items.some(item=>item.status!=='published'||item.stock<item.quantity))throw new ConflictException('One or more products are no longer available in that quantity. Refresh your cart and try again.');
      const id=randomUUID(),subtotalPaise=items.reduce((sum,item)=>sum+item.pricePaise*item.quantity,0);
      const lineItems=items.map(({id:productId,sku,name,brand,packSize,pricePaise,quantity})=>({productId,sku,name,brand,packSize,pricePaise,quantity}));
      await c.query(`INSERT INTO store_order_requests(id,customer_id,request_id,cart_revision,line_items,subtotal_paise) VALUES($1,$2,$3,$4,$5,$6)`,[id,user.id,body.requestId,body.cartRevision,JSON.stringify(lineItems),subtotalPaise]);
      await c.query('COMMIT');return{id,status:'requested',duplicate:false};
    }catch(e){await c.query('ROLLBACK');if((e as {code?:string}).code==='23505'){const prior=(await this.db.pool.query('SELECT id FROM store_order_requests WHERE customer_id=$1 AND request_id=$2',[user.id,body.requestId])).rows[0];if(prior)return{id:prior.id,status:'requested',duplicate:true};}throw e;}finally{c.release();}
  }
  async ownerOrders(user:User,status?:string){
    admin(user);const valid=status&&['requested','reviewed','closed'].includes(status)?status:null;
    const rows=(await this.db.pool.query(`SELECT o.id,o.status,o.line_items AS "lineItems",o.subtotal_paise AS "subtotalPaise",o.revision,o.created_at AS "createdAt",o.updated_at AS "updatedAt",u.display_name AS "customerName",u.email AS "customerEmail" FROM store_order_requests o JOIN users u ON u.id=o.customer_id WHERE ($1::text IS NULL OR o.status=$1) ORDER BY CASE o.status WHEN 'requested' THEN 0 WHEN 'reviewed' THEN 1 ELSE 2 END,o.created_at DESC LIMIT 200`,[valid])).rows;
    return{orders:rows,currency:'INR',paymentEnabled:false,deliveryEnabled:false};
  }
  async updateOrder(user:User,value:string,input:unknown){
    admin(user);const id=parse(z.uuid(),value),body=parse(orderStatusSchema,input),client=await this.db.pool.connect();
    try{
      await client.query('BEGIN');await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,15016))',[user.id]);
      const oldEvent=(await client.query('SELECT order_id,next_status FROM store_order_events WHERE actor_id=$1 AND request_id=$2',[user.id,body.requestId])).rows[0];
      if(oldEvent){if(oldEvent.order_id!==id||oldEvent.next_status!==body.status)throw new ConflictException('This update reference was used for another order change.');const current=(await client.query('SELECT revision,status FROM store_order_requests WHERE id=$1',[id])).rows[0];await client.query('COMMIT');return{ id,...current,duplicate:true};}
      const order=(await client.query('SELECT status,revision FROM store_order_requests WHERE id=$1 FOR UPDATE',[id])).rows[0];
      if(!order)throw new NotFoundException('Order request not found.');
      if(order.revision!==body.revision)throw new ConflictException('This request changed. Refresh the order list before updating it.');
      if(order.status==='closed')throw new ConflictException('Closed requests cannot be reopened.');
      if(order.status===body.status){await client.query('COMMIT');return{id,status:order.status,revision:order.revision,duplicate:true};}
      const revision=order.revision+1;
      await client.query('UPDATE store_order_requests SET status=$2,revision=$3,updated_at=now() WHERE id=$1',[id,body.status,revision]);
      await client.query('INSERT INTO store_order_events(id,order_id,actor_id,request_id,previous_status,next_status) VALUES($1,$2,$3,$4,$5,$6)',[randomUUID(),id,user.id,body.requestId,order.status,body.status]);
      await client.query('COMMIT');return{id,status:body.status,revision,duplicate:false};
    }catch(e){await client.query('ROLLBACK');throw e;}finally{client.release();}
  }
}

@Controller('store')
@UseGuards(AuthGuard)
export class StoreController {
  constructor(@Inject(StoreService)private readonly store:StoreService){}
  @Get('products') catalogue(@Req()r:{user:User},@Query()query:unknown){return this.store.catalogue(r.user,query);}
  @Get('products/:id') detail(@Req()r:{user:User},@Param('id')id:string){return this.store.detail(r.user,id);}
}
@Controller('me/cart')
@UseGuards(AuthGuard)
export class CartController {
  constructor(@Inject(StoreService)private readonly store:StoreService){}
  @Get() get(@Req()r:{user:User}){return this.store.cart(r.user);}
  @Put(':id') set(@Req()r:{user:User},@Param('id')id:string,@Body()body:unknown){return this.store.setQuantity(r.user,id,body);}
}
@Controller('me/store-orders')
@UseGuards(AuthGuard)
export class CustomerStoreOrdersController {
  constructor(@Inject(StoreService)private readonly store:StoreService){}
  @Get() list(@Req()r:{user:User}){return this.store.customerOrders(r.user);}
  @Put() request(@Req()r:{user:User},@Body()body:unknown){return this.store.requestOrder(r.user,body);}
}
@Controller('staff/store')
@UseGuards(AuthGuard)
export class StoreAdminController {
  constructor(@Inject(StoreService)private readonly store:StoreService){}
  @Get('products') list(@Req()r:{user:User},@Query()query:unknown){return this.store.catalogue(r.user,query,true);}
  @Put('products/:id') save(@Req()r:{user:User},@Param('id')id:string,@Body()body:unknown){return this.store.saveProduct(r.user,id,body);}
  @Get('orders') orders(@Req()r:{user:User},@Query('status')status?:string){return this.store.ownerOrders(r.user,status);}
  @Put('orders/:id') updateOrder(@Req()r:{user:User},@Param('id')id:string,@Body()body:unknown){return this.store.updateOrder(r.user,id,body);}
}
