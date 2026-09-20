# 数据字典（data_dictionary.md）

> 本作品集 8 张业务表的字段说明、主外键、取值说明。面向读者：让任何人能看懂表的语义与关联。

---

## 表总览与血缘

```
customers ──1:N──> orders ──1:N──> order_items ──N:1──> products
                                      │                      │
                                      │N:1                   └──N:1──> category_name
                                      └──> sellers
orders ──1:N──> order_payments
orders ──1:N──> order_reviews
```

---

## 1. customers（客户）

| 字段 | 类型 | 含义 | 主/外键 |
|------|------|------|---------|
| customer_id | string | 订单级客户标识（每单一个） | PK |
| customer_unique_id | string | 真实用户唯一标识 | 逻辑用户键 |
| customer_zip_code_prefix | int | 邮编前缀 | — |
| customer_city | string | 城市 | — |
| customer_state | string | 州（如 SP/RJ/MG） | — |

> 关键：`customer_id` 一行=一个订单客户，`customer_unique_id` 才代表真实用户（可多行）。

## 2. orders（订单）

| 字段 | 类型 | 含义 | 主/外键 |
|------|------|------|---------|
| order_id | string | 订单号 | PK |
| customer_id | string | 客户 | FK→customers |
| order_status | string | 状态(delivered/canceled/… ) | — |
| order_purchase_timestamp | datetime | 下单时间 | — |
| order_approved_at | datetime | 审核通过 | — |
| order_delivered_carrier_date | datetime | 交承运商 | — |
| order_delivered_customer_date | datetime | 送达客户 | — |
| order_estimated_delivery_date | datetime | 预计送达 | — |

## 3. order_items（订单商品明细）

| 字段 | 类型 | 含义 | 主/外键 |
|------|------|------|---------|
| order_id | string | 订单 | PK(复合) |
| order_item_id | int | 明细序号 | PK(复合) |
| product_id | string | 商品 | FK→products |
| seller_id | string | 卖家 | FK→sellers |
| shipping_limit_date | datetime | 发货时限 | — |
| price | decimal | 商品成交价 | — |
| freight_value | decimal | 运费 | — |

> 一张订单可有多行明细（多商品订单）。统计订单量必须 `COUNT(DISTINCT order_id)`。

## 4. order_payments（订单支付）

| 字段 | 类型 | 含义 | 主/外键 |
|------|------|------|---------|
| order_id | string | 订单 | PK(复合) |
| payment_sequential | int | 支付序号（分期=多行） | PK(复合) |
| payment_type | string | credit_card/boleto/… | — |
| payment_installments | int | 分期期数 | — |
| payment_value | decimal | 本笔支付金额 | — |

> 一单可多笔支付（分期/多次），直接 SUM 会重复统计 GMV，须先按 order_id 聚合或绕过此表算 GMV。

## 5. order_reviews（订单评价）

| 字段 | 类型 | 含义 | 主/外键 |
|------|------|------|---------|
| review_id | string | 评价号 | PK |
| order_id | string | 订单 | FK→orders |
| review_score | int | 评分 1~5 | — |
| review_comment_title | text | 标题 | — |
| review_comment_message | text | 内容 | — |
| review_creation_date | datetime | 评价时间 | — |
| review_answer_timestamp | datetime | 答复时间 | — |

> 一个订单可有多条评价；原数据 review_id 有 814 重复行，清洗期已去重；平均分须按 order_id 聚合。

## 6. products（商品）

| 字段 | 类型 | 含义 | 主/外键 |
|------|------|------|---------|
| product_id | string | 商品号 | PK |
| product_category_name | string | 品类(葡语) | FK→category |
| product_name_lenght / description_lenght / photos_qty / weight_g / length_cm / height_cm / width_cm | float | 名称/描述长度、图片数、重量、长宽高(cm) | — |

## 7. sellers（卖家）

| 字段 | 类型 | 含义 | 主/外键 |
|------|------|------|---------|
| seller_id | string | 卖家号 | PK |
| seller_zip_code_prefix | int | 邮编前缀 | — |
| seller_city | string | 城市 | — |
| seller_state | string | 州 | — |

## 8. category_name（品类翻译）

| 字段 | 类型 | 含义 | 主/外键 |
|------|------|------|---------|
| product_category_name | string | 品类(葡语) | PK |
| product_category_name_english | string | 品类(英语) | — |

> 分析时用英语品类名对外展示，避免葡语读者看不懂。

---

## 表行数（清洗后导入 MySQL 值）

| 表 | 行数 | 备注 |
|----|------|------|
| customers | 99,441 | customer_unique_id 去重 96,096 |
| orders | 99,441 | delivered 96,478 |
| order_items | 112,650 | 明细 |
| order_payments | 103,886 | 含分期多笔 |
| order_reviews | 98,410 | review_id 去重后 |
| products | 32,951 | |
| sellers | 3,095 | |
| category_name | 71 | |