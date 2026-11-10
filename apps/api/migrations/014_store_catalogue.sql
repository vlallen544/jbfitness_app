CREATE TABLE store_products (
  id uuid PRIMARY KEY,
  sku text NOT NULL UNIQUE,
  name text NOT NULL,
  brand text NOT NULL,
  category text NOT NULL CHECK (category IN ('protein','creatine','vitamins','other')),
  description text NOT NULL,
  ingredients text NOT NULL,
  allergen_notes text NOT NULL,
  pack_size text NOT NULL,
  serving_size text NOT NULL,
  image_url text,
  price_paise integer NOT NULL CHECK (price_paise BETWEEN 1 AND 10000000),
  stock integer NOT NULL CHECK (stock BETWEEN 0 AND 1000000),
  status text NOT NULL CHECK (status IN ('draft','published','archived')),
  revision integer NOT NULL CHECK (revision>0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX store_products_catalogue ON store_products(status,category,name,id);
CREATE TABLE store_carts (
  customer_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  revision integer NOT NULL DEFAULT 0 CHECK (revision>=0)
);
CREATE TABLE store_cart_items (
  customer_id uuid NOT NULL REFERENCES store_carts(customer_id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES store_products(id),
  quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 10),
  PRIMARY KEY(customer_id,product_id)
);
CREATE TABLE store_changes (
  actor_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  payload_hash text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(actor_id,request_id)
);
ALTER TABLE store_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_changes ENABLE ROW LEVEL SECURITY;
