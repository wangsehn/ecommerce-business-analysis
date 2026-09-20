# 数据字典（data_dictionary.md）

> 本作品集使用 Olist 公开电商数据的 8 张业务表。这里重点说明“每一行代表什么”和“连接后会不会改变粒度”。

---

## 表关系与粒度

```text
customer_unique_id（同一实际客户的跨订单标识）
        │ 1:N
        ▼
customers(customer_id：每个订单对应的客户键)
        │ 1:1（在该数据集中用于连接 orders）
        ▼
orders(order_id)
   ├── 1:N ──> order_items ── N:1 ──> products
   │                         └─ N:1 ──> sellers
   ├── 1:N ──> order_payments
   └── 1:N ──> order_reviews
```

> 关键区别：`customer_id` 是订单级客户键；同一个实际客户再次下单时会得到新的 `customer_id`。跨订单识别复购应使用 `customer_unique_id`。

## 1. customers

| 字段 | 含义 | 备注 |
|---|---|---|
| customer_id | 订单级客户键 | PK；用于连接 orders |
| customer_unique_id | 跨订单客户标识 | 复购/客户级分析使用 |
| customer_zip_code_prefix | 邮编前缀 | 地理字段 |
| customer_city | 城市 | — |
| customer_state | 州 | — |

## 2. orders

| 字段 | 含义 |
|---|---|
| order_id | 订单主键 |
| customer_id | 订单级客户键，FK→customers |
| order_status | 订单状态 |
| order_purchase_timestamp | 下单时间 |
| order_delivered_customer_date | 实际送达时间 |
| order_estimated_delivery_date | 预计送达时间 |

## 3. order_items

一行 = 一张订单中的一个商品明细。

| 字段 | 含义 |
|---|---|
| order_id + order_item_id | 复合键 |
| product_id | 商品 |
| seller_id | 卖家 |
| price | 商品成交价 |
| freight_value | 对应明细运费 |

> 一单可以有多行 item；订单量必须按 `COUNT(DISTINCT order_id)` 统计。

## 4. order_payments

一行 = 一条支付记录。

| 字段 | 含义 |
|---|---|
| order_id | 订单 |
| payment_sequential | 同一订单多条支付记录的顺序 |
| payment_type | 支付方式 |
| payment_installments | 分期期数 |
| payment_value | 本条支付记录金额 |

> `payment_sequential` 不等于“分期序号”。分期信息在 `payment_installments`。一单可有多条支付记录/支付方式；分析支付金额时应先按订单聚合。本文的商品 GMV 定义来自 `order_items.price`，不能用 `payment_value` 直接替代，因为两者业务口径不同。

## 5. order_reviews

一行 = 一条评价记录。一个订单可能出现多条评价记录。

> 评分比较时先按 `order_id` 聚合成“订单级评分”，再进入地区/卖家/支付等分析，避免同单多评重复加权。

## 6. products

商品主数据，主键 `product_id`，包含品类、尺寸、重量、图片数量等字段。

## 7. sellers

卖家主数据，主键 `seller_id`，包含城市与州信息。

## 8. category_name

葡萄牙语品类名与英语品类名的映射表。

---

## 当前导入规模

| 表 | 行数 | 备注 |
|---|---:|---|
| customers | 99,441 | `customer_unique_id` 去重 96,096 |
| orders | 99,441 | delivered 96,478 |
| order_items | 112,650 | 商品明细 |
| order_payments | 103,886 | 支付记录 |
| order_reviews | 98,410 | 清洗后的评价记录 |
| products | 32,951 | 商品 |
| sellers | 3,095 | 卖家 |
| category_name | 71 | 品类翻译 |
