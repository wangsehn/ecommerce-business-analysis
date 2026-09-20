-- ============================================================================
-- 06_logistics_analysis.sql  ——  物流与履约分析（页面 4 数据层）
-- ----------------------------------------------------------------------------
-- 业务问题：配送到底快不快、准不准？哪里最慢（地区/卖家）？
--           履约时效与评分是否存在明显关联？
--
-- 统一口径：
--   - 配送时长(天) = DATEDIFF(实际送达日期, 下单日期)
--   - 准时/超时采用“日粒度”：
--       准时 = DATE(实际送达) <= DATE(预计送达)
--       超时 = DATE(实际送达) >  DATE(预计送达)
--     这样与 DATEDIFF 的超时天数分桶完全一致，不把“预计日当天晚于 00:00 到货”误判为超时。
--   - 只统计 order_status='delivered' 且相关日期非空的订单。
--   - 卖家分析先压到 seller_id + order_id 粒度，避免多商品订单重复计入分子。
-- ============================================================================
USE ecommerce_bas;

-- 1) 整体配送时长：平均 / 中位
WITH delivery AS (
    SELECT order_id,
           DATEDIFF(DATE(order_delivered_customer_date), DATE(order_purchase_timestamp)) AS delivery_days
    FROM orders
    WHERE order_status='delivered'
      AND order_delivered_customer_date IS NOT NULL
)
SELECT
    ROUND(AVG(delivery_days),1) AS `平均配送天数`,
    ROUND((
        SELECT delivery_days
        FROM (
            SELECT delivery_days,
                   ROW_NUMBER() OVER (ORDER BY delivery_days) AS rn,
                   COUNT(*) OVER () AS cnt
            FROM delivery
        ) x
        WHERE rn = CEIL(cnt/2)
    ),1) AS `中位配送天数`,
    COUNT(*) AS `已配送订单`
FROM delivery;

-- 2) 准时率 / 超时率：统一使用日粒度口径
WITH delivery AS (
    SELECT order_id,
           CASE
               WHEN DATE(order_delivered_customer_date) > DATE(order_estimated_delivery_date) THEN 1
               ELSE 0
           END AS is_late
    FROM orders
    WHERE order_status='delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
)
SELECT
    COUNT(*) AS `已配送订单`,
    SUM(is_late=0) AS `准时单`,
    SUM(is_late=1) AS `超时单`,
    ROUND(AVG(is_late)*100,2) AS `超时率%`,
    ROUND((1-AVG(is_late))*100,2) AS `准时率%`
FROM delivery;

-- 3) 超时天数分布：与第 2 条使用同一日期口径
WITH delivery AS (
    SELECT order_id,
           DATEDIFF(DATE(order_delivered_customer_date), DATE(order_estimated_delivery_date)) AS late_days
    FROM orders
    WHERE order_status='delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
)
SELECT
    CASE
        WHEN late_days <= 0 THEN '准时'
        WHEN late_days <= 3 THEN '超时1-3天'
        WHEN late_days <= 7 THEN '超时4-7天'
        ELSE '超时7天以上'
    END AS `档位`,
    COUNT(*) AS `订单数`,
    ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) AS `占比%`
FROM delivery
GROUP BY `档位`
ORDER BY MIN(late_days);

-- 4) 各州物流表现
WITH delivery AS (
    SELECT o.order_id,
           c.customer_state,
           DATEDIFF(DATE(o.order_delivered_customer_date), DATE(o.order_purchase_timestamp)) AS delivery_days,
           CASE
               WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date) THEN 1
               ELSE 0
           END AS is_late
    FROM orders o
    JOIN customers c USING (customer_id)
    WHERE o.order_status='delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    customer_state AS `州`,
    COUNT(*) AS `配送订单`,
    ROUND(AVG(delivery_days),1) AS `平均配送天数`,
    ROUND(AVG(is_late)*100,2) AS `超时率%`
FROM delivery
GROUP BY customer_state
HAVING COUNT(*) >= 200
ORDER BY `超时率%` DESC
LIMIT 12;

-- 5) 卖家端物流表现
-- 先 DISTINCT seller_id + order_id，防止同一卖家一单多 item 导致超时分子被重复累加。
WITH seller_order AS (
    SELECT DISTINCT seller_id, order_id
    FROM order_items
),
seller_delivery AS (
    SELECT so.seller_id,
           so.order_id,
           DATEDIFF(DATE(o.order_delivered_customer_date), DATE(o.order_purchase_timestamp)) AS delivery_days,
           CASE
               WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date) THEN 1
               ELSE 0
           END AS is_late
    FROM seller_order so
    JOIN orders o ON o.order_id = so.order_id
    WHERE o.order_status='delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    seller_id AS `卖家`,
    COUNT(*) AS `订单量`,
    ROUND(AVG(is_late)*100,2) AS `延迟率%`,
    ROUND(AVG(delivery_days),1) AS `平均配送天数`
FROM seller_delivery
GROUP BY seller_id
HAVING COUNT(*) >= 20
ORDER BY `延迟率%` DESC
LIMIT 12;

-- 6) 配送时长档位 vs 评分
WITH order_review AS (
    SELECT order_id, AVG(review_score) AS order_score
    FROM order_reviews
    GROUP BY order_id
),
delivery AS (
    SELECT o.order_id,
           DATEDIFF(DATE(o.order_delivered_customer_date), DATE(o.order_purchase_timestamp)) AS delivery_days,
           CASE
               WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date) THEN 1
               ELSE 0
           END AS is_late,
           r.order_score
    FROM orders o
    JOIN order_review r USING (order_id)
    WHERE o.order_status='delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    CASE
        WHEN delivery_days <= 3 THEN '<=3天'
        WHEN delivery_days <= 7 THEN '4-7天'
        WHEN delivery_days <= 10 THEN '8-10天'
        WHEN delivery_days <= 15 THEN '11-15天'
        ELSE '>15天'
    END AS `配送时长档`,
    COUNT(*) AS `订单数`,
    ROUND(AVG(order_score),2) AS `平均评分`,
    SUM(is_late) AS `超时单`,
    ROUND(AVG(is_late)*100,2) AS `超时率%`
FROM delivery
GROUP BY `配送时长档`
ORDER BY MIN(delivery_days);

-- 7) 准时 vs 超时订单评分
WITH order_review AS (
    SELECT order_id, AVG(review_score) AS order_score
    FROM order_reviews
    GROUP BY order_id
),
delivery AS (
    SELECT o.order_id,
           CASE
               WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date) THEN '超时'
               ELSE '准时'
           END AS fulfillment,
           r.order_score
    FROM orders o
    JOIN order_review r USING (order_id)
    WHERE o.order_status='delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    fulfillment AS `履约`,
    COUNT(*) AS `订单数`,
    ROUND(AVG(order_score),2) AS `平均评分`
FROM delivery
GROUP BY fulfillment;
