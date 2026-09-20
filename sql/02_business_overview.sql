-- ============================================================================
-- 02_business_overview.sql  ——  经营总览（页面 1 的数据层）
-- ----------------------------------------------------------------------------
-- 业务问题：管理层最先关心"盘子多大、增长稳不稳、异常在哪"。
-- 指标口径（本作品集统一，见 docs/metric_definition.md）：
--   - 有效订单 = order_status = 'delivered'（已完成交付）
--   - GMV = 有效订单的商品售价合计 SUM(order_items.price)，不含运费（平台收入口径）
--   - AOV(客单价) = GMV / 有效订单数（按 order_id 去重，多商品订单只算一张单）
-- SQL思路：多商品订单会让 orders×items 产生多行，因此订单量、AOV 一律用
--          COUNT(DISTINCT order_id)；GMV 用 SUM(price)（每行都是单条商品价）。
-- ============================================================================
USE ecommerce_bas;

-- 1) 核心 KPI：用 CTE 先筛出有效订单，避免反复写 WHERE
WITH valid_orders AS (
    SELECT o.order_id, o.order_status, o.order_purchase_timestamp,
           o.order_delivered_customer_date, o.order_estimated_delivery_date
    FROM orders o
    WHERE o.order_status = 'delivered'
),
valid_items AS (
    SELECT oi.order_id, oi.price, oi.freight_value
    FROM order_items oi
    JOIN valid_orders v ON oi.order_id = v.order_id
)
SELECT
    ROUND(SUM(price), 2)                                        AS `GMV(商品价,不含运费)`,
    ROUND(SUM(freight_value), 2)                                AS `运费总额`,
    COUNT(DISTINCT order_id)                                   AS `有效订单数`,
    ROUND(SUM(price) / COUNT(DISTINCT order_id), 2)            AS `AOV客单价`,
    (SELECT COUNT(DISTINCT customer_unique_id) FROM customers) AS `注册用户数`,
    (SELECT COUNT(DISTINCT seller_id) FROM sellers)            AS `卖家数`,
    (SELECT COUNT(DISTINCT product_id) FROM products)          AS `在售商品数`
FROM valid_items;

-- 2) 全部订单口径对比（含 cancelled/unavailable），证明为什么必须过滤：
--    差异即为"下单未成交"的虚增部分。
SELECT
    COUNT(DISTINCT order_id) AS `全部订单数`,
    ROUND(SUM(price),2)      AS `全部订单GMV(含未交付)`,
    ROUND(SUM(price)/COUNT(DISTINCT order_id),2) AS `整体AOV(含未交付)`,
    (SELECT ROUND(SUM(price),2) FROM order_items
       JOIN orders USING (order_id)
      WHERE order_status='delivered') AS `仅交付GMV`
FROM order_items JOIN orders USING (order_id);

-- 3) 月度经营趋势：GMV、订单量、AOV、贡献度
WITH valid AS (
    SELECT o.order_id,
           DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS ym,
           o.order_purchase_timestamp
    FROM orders o
    WHERE o.order_status = 'delivered'
),
fact AS (
    SELECT v.ym, v.order_id, oi.price
    FROM valid v
    JOIN order_items oi USING (order_id)
)
SELECT
    ym AS `月份`,
    COUNT(DISTINCT order_id)                              AS `订单量`,
    ROUND(SUM(price), 2)                                  AS `GMV`,
    ROUND(SUM(price) / COUNT(DISTINCT order_id), 2)       AS `AOV`,
    ROUND(SUM(price) / SUM(SUM(price)) OVER() * 100, 2)   AS `GMV占比%`
FROM fact
GROUP BY ym
ORDER BY ym;

-- 4) 月度环比：用 LAG 看增长是否平稳、哪些月份异常（突增/突降）
WITH m AS (
    SELECT DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS ym,
           SUM(oi.price) AS gmv
    FROM orders o
    JOIN order_items oi USING (order_id)
    WHERE o.order_status = 'delivered'
    GROUP BY ym
)
SELECT ym,
       ROUND(gmv, 2)                              AS gmv,
       ROUND(LAG(gmv) OVER (ORDER BY ym), 2)      AS prev_gmv,
       ROUND((gmv - LAG(gmv) OVER (ORDER BY ym)) / LAG(gmv) OVER (ORDER BY ym) * 100, 2) AS `环比%`
FROM m
ORDER BY ym;

-- 5) 地区(州)表现：GMV、订单、AOV、用户分布（有效订单）
SELECT
    c.customer_state AS `州`,
    COUNT(DISTINCT o.order_id)                        AS `订单量`,
    ROUND(SUM(oi.price), 2)                           AS `GMV`,
    ROUND(SUM(oi.price) / COUNT(DISTINCT o.order_id), 2) AS `AOV`,
    COUNT(DISTINCT c.customer_unique_id)              AS `用户数`,
    ROUND(SUM(oi.price) / SUM(SUM(oi.price)) OVER() * 100, 2) AS `GMV占比%`
FROM customers c
JOIN orders o        ON o.customer_id = c.customer_id AND o.order_status = 'delivered'
JOIN order_items oi  USING (order_id)
GROUP BY c.customer_state
ORDER BY `GMV` DESC
LIMIT 15;

-- 6) 品类结构：GMV 与新客获取（页面 1 品类结构）
SELECT
    COALESCE(cn.product_category_name_english, p.product_category_name, 'unknown') AS `品类(英)`,
    COUNT(DISTINCT oi.order_id) AS `订单量`,
    ROUND(SUM(oi.price), 2)     AS `GMV`
FROM order_items oi
JOIN products p        USING (product_id)
JOIN orders o          ON o.order_id = oi.order_id AND o.order_status = 'delivered'
LEFT JOIN category_name cn ON cn.product_category_name = p.product_category_name
GROUP BY cn.product_category_name_english, p.product_category_name
ORDER BY `GMV` DESC
LIMIT 20;