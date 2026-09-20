-- ============================================================================
-- 07_review_analysis.sql  ——  评价与体验分析
-- ----------------------------------------------------------------------------
-- 原则：
--   1) 评价先聚合到 order_id 粒度，避免同单多评重复加权；
--   2) 价格段先聚合到订单金额，再分档，避免一单多商品跨档重复；
--   3) 支付方式先压到 order_id + payment_type 粒度，避免同一订单同一支付类型多记录重复。
-- ============================================================================
USE ecommerce_bas;

-- 订单级评分
WITH order_review AS (
    SELECT order_id, AVG(review_score) AS order_score
    FROM order_reviews
    GROUP BY order_id
)
SELECT
    COUNT(*) AS `评价订单`,
    ROUND(AVG(order_score),2) AS `平均分`,
    SUM(order_score<=2) AS `差评单`,
    ROUND(AVG(order_score<=2)*100,2) AS `差评率%`,
    SUM(order_score<=1) AS `一星单`
FROM order_review;

-- 2) 订单金额段 vs 评分：先算 delivered 订单商品金额
WITH order_value AS (
    SELECT oi.order_id, SUM(oi.price) AS order_gmv
    FROM order_items oi
    JOIN orders o
      ON o.order_id=oi.order_id
     AND o.order_status='delivered'
    GROUP BY oi.order_id
),
order_review AS (
    SELECT order_id, AVG(review_score) AS order_score
    FROM order_reviews
    GROUP BY order_id
)
SELECT
    CASE
        WHEN ov.order_gmv<50 THEN '<50'
        WHEN ov.order_gmv<100 THEN '50-100'
        WHEN ov.order_gmv<200 THEN '100-200'
        WHEN ov.order_gmv<400 THEN '200-400'
        ELSE '>400'
    END AS `订单金额档`,
    COUNT(*) AS `订单量`,
    ROUND(AVG(r.order_score),2) AS `平均评分`
FROM order_value ov
JOIN order_review r USING (order_id)
GROUP BY `订单金额档`
ORDER BY MIN(ov.order_gmv);

-- 3) 支付方式 vs 评分
-- payment_sequential 表示同一订单可有多个支付记录；先去重为 order_id + payment_type 再统计。
WITH payment_order AS (
    SELECT DISTINCT order_id, payment_type
    FROM order_payments
    WHERE payment_type IS NOT NULL
),
order_review AS (
    SELECT order_id, AVG(review_score) AS order_score
    FROM order_reviews
    GROUP BY order_id
)
SELECT
    p.payment_type AS `支付方式`,
    COUNT(*) AS `订单量`,
    ROUND(AVG(r.order_score),2) AS `平均评分`,
    ROUND(AVG(r.order_score<=2)*100,2) AS `差评率%`
FROM payment_order p
JOIN order_review r USING (order_id)
GROUP BY p.payment_type
ORDER BY `订单量` DESC;

-- 4) 品类评分：先去重到 品类 + 订单 粒度，避免同类多 item 重复加权同一订单评分
WITH category_order AS (
    SELECT DISTINCT
           COALESCE(cn.product_category_name_english,p.product_category_name,'unknown') AS category,
           oi.order_id
    FROM order_items oi
    JOIN orders o
      ON o.order_id=oi.order_id
     AND o.order_status='delivered'
    JOIN products p USING (product_id)
    LEFT JOIN category_name cn USING (product_category_name)
),
order_review AS (
    SELECT order_id, AVG(review_score) AS order_score
    FROM order_reviews
    GROUP BY order_id
),
category_score AS (
    SELECT co.category,
           COUNT(*) AS review_orders,
           AVG(r.order_score) AS avg_score
    FROM category_order co
    JOIN order_review r USING (order_id)
    GROUP BY co.category
)
SELECT category AS `品类`,
       review_orders AS `有评价订单`,
       ROUND(avg_score,2) AS `平均评分`
FROM category_score
WHERE review_orders >= 100
ORDER BY avg_score DESC;
