-- ============================================================================
-- 05_seller_analysis.sql  ——  卖家分析（页面 3 数据层之二）
-- ----------------------------------------------------------------------------
-- 业务问题：平台卖家贡献是分散还是集中？少数头部卖家是否贡献大部分 GMV？
--           是否存在“高 GMV + 低评分”或“高订单量 + 高延迟”的卖家风险？
--
-- 口径：
--   - 只统计 order_status='delivered' 的有效订单。
--   - 卖家梯队按 GMV 排名百分位划分：前 2% = 头部，2%~20% = 腰部，其余 = 长尾。
--   - 评分分析必须先去重到 seller_id + order_id 粒度，避免同一卖家在一单中有多个 item
--     时把同一个订单评分重复加权。
-- ============================================================================
USE ecommerce_bas;

-- 1) 卖家 GMV 集中度：看 Top 卖家贡献与累计 GMV 占比
WITH seller_gmv AS (
    SELECT oi.seller_id,
           SUM(oi.price) AS gmv,
           COUNT(DISTINCT oi.order_id) AS orders
    FROM order_items oi
    JOIN orders o
      ON o.order_id = oi.order_id
     AND o.order_status = 'delivered'
    GROUP BY oi.seller_id
),
tot AS (
    SELECT SUM(gmv) AS total_gmv FROM seller_gmv
)
SELECT seller_id AS `卖家`,
       ROUND(gmv,2) AS `GMV`,
       orders AS `订单量`,
       ROUND(gmv/(SELECT total_gmv FROM tot)*100,2) AS `占GMV%`,
       ROUND(SUM(gmv) OVER (ORDER BY gmv DESC)/(SELECT total_gmv FROM tot)*100,2) AS `累计GMV%`
FROM seller_gmv
ORDER BY gmv DESC
LIMIT 15;

-- 2) 卖家分层：头部/腰部/长尾规模与 GMV 贡献
WITH seller_gmv AS (
    SELECT oi.seller_id,
           SUM(oi.price) AS gmv,
           COUNT(DISTINCT oi.order_id) AS orders
    FROM order_items oi
    JOIN orders o
      ON o.order_id = oi.order_id
     AND o.order_status = 'delivered'
    GROUP BY oi.seller_id
),
ranked AS (
    SELECT seller_id,
           gmv,
           orders,
           ROW_NUMBER() OVER (ORDER BY gmv DESC) AS rn,
           COUNT(*) OVER () AS total
    FROM seller_gmv
)
SELECT
    CASE
        WHEN rn <= CEIL(total*0.02) THEN '头部(前2%)'
        WHEN rn <= CEIL(total*0.20) THEN '腰部(2-20%)'
        ELSE '长尾'
    END AS `梯队`,
    COUNT(*) AS `卖家数`,
    ROUND(SUM(gmv),2) AS `梯队GMV`,
    ROUND(SUM(gmv)/SUM(SUM(gmv)) OVER()*100,2) AS `占GMV%`
FROM ranked
GROUP BY `梯队`
ORDER BY `占GMV%` DESC;

-- 3) 卖家销售频次结构
WITH seller_orders AS (
    SELECT oi.seller_id,
           COUNT(DISTINCT oi.order_id) AS orders
    FROM order_items oi
    JOIN orders o
      ON o.order_id = oi.order_id
     AND o.order_status = 'delivered'
    GROUP BY oi.seller_id
)
SELECT
    CASE
        WHEN orders = 1 THEN '1单'
        WHEN orders <= 5 THEN '2-5单'
        WHEN orders <= 20 THEN '6-20单'
        ELSE '20+单'
    END AS `累计下单档位`,
    COUNT(*) AS `卖家数`,
    ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) AS `占比%`
FROM seller_orders
GROUP BY `累计下单档位`
ORDER BY MIN(orders);

-- 4) 高 GMV 但低评分卖家
-- 先把 item 明细压到 seller_id + order_id 粒度，再连接订单级评分，避免同单多件商品重复加权评分。
WITH seller_order AS (
    SELECT DISTINCT oi.seller_id, oi.order_id
    FROM order_items oi
    JOIN orders o
      ON o.order_id = oi.order_id
     AND o.order_status = 'delivered'
),
seller_sales AS (
    SELECT oi.seller_id,
           ROUND(SUM(oi.price),2) AS gmv,
           COUNT(DISTINCT oi.order_id) AS orders
    FROM order_items oi
    JOIN orders o
      ON o.order_id = oi.order_id
     AND o.order_status = 'delivered'
    GROUP BY oi.seller_id
),
order_review AS (
    SELECT order_id, AVG(review_score) AS order_score
    FROM order_reviews
    GROUP BY order_id
),
seller_review AS (
    SELECT so.seller_id,
           ROUND(AVG(orv.order_score),2) AS avg_score,
           COUNT(*) AS n_review_orders
    FROM seller_order so
    JOIN order_review orv ON orv.order_id = so.order_id
    GROUP BY so.seller_id
)
SELECT ss.seller_id AS `卖家`,
       ss.gmv AS `GMV`,
       ss.orders AS `订单量`,
       sr.avg_score AS `平均评分`,
       sr.n_review_orders AS `有评价订单数`,
       CASE
           WHEN sr.avg_score <= 4 AND ss.gmv > 30000 THEN '⚠风险(高GMV低分)'
           ELSE '正常'
       END AS `标记`
FROM seller_sales ss
LEFT JOIN seller_review sr USING (seller_id)
WHERE ss.orders >= 10
  AND sr.avg_score IS NOT NULL
ORDER BY ss.gmv DESC
LIMIT 25;

-- 5) 卖家地域分布
SELECT seller_state AS `州`,
       COUNT(*) AS `卖家数`,
       ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) AS `占比%`
FROM sellers
GROUP BY seller_state
ORDER BY `卖家数` DESC
LIMIT 12;
