-- ============================================================================
-- 04_product_analysis.sql  ——  商品与品类分析（页面 3 数据层之一）
-- ----------------------------------------------------------------------------
-- 业务问题：哪些品类贡献了主要 GMV / 订单？高 GMV 是不是高销量？低价高频 vs 高价低频
--           怎么选？评分高低和销量有无关系？——用于选品与品类运营。
-- 口径：仅统计有效订单（order_status='delivered'）。
-- SQL技巧：多处用窗口函数 RANK/DENSE_RANK、SUM OVER 计算集中度，避免只做排行榜。
-- ============================================================================
USE ecommerce_bas;

-- 1) 品类 GMV 与订单量、客单量：识别"高GMV/低订单"(高价低频) vs "低GMV/高订单"(低价高频)
WITH cat AS (
    SELECT
        COALESCE(cn.product_category_name_english, p.product_category_name, 'unknown') AS cname,
        COUNT(DISTINCT oi.order_id) AS orders,
        SUM(oi.price)               AS gmv,
        COUNT(oi.product_id)        AS units
    FROM order_items oi
    JOIN products p   USING (product_id)
    JOIN orders o     ON o.order_id=oi.order_id AND o.order_status='delivered'
    LEFT JOIN category_name cn ON cn.product_category_name = p.product_category_name
    GROUP BY cn.product_category_name_english, p.product_category_name
)
SELECT
    cname AS `品类`,
    orders AS `订单量`,
    ROUND(gmv,2) AS `GMV`,
    units AS `销量(件)`,
    ROUND(gmv/orders,2) AS `订单均价`,
    ROUND(units/orders,2) AS `件均单量`,
    RANK() OVER (ORDER BY gmv DESC)  AS `GMV名次`,
    DENSE_RANK() OVER (ORDER BY units DESC) AS `销量名次`
FROM cat
ORDER BY gmv DESC
LIMIT 20;

-- 2) 品类 GMV 集中度：top5 品类占 GMV 比例（SUM OVER 累计占比）
WITH cat AS (
    SELECT COALESCE(cn.product_category_name_english,p.product_category_name) AS cname,
           SUM(oi.price) AS gmv
    FROM order_items oi
    JOIN products p USING (product_id)
    JOIN orders o ON o.order_id=oi.order_id AND o.order_status='delivered'
    LEFT JOIN category_name cn ON cn.product_category_name=p.product_category_name
    GROUP BY cn.product_category_name_english, p.product_category_name
),
tot AS (SELECT SUM(gmv) total FROM cat)
SELECT cname AS `品类`,
       ROUND(gmv,2) AS `GMV`,
       ROUND(gmv/(SELECT total FROM tot)*100,2) AS `占GMV%`,
       ROUND(SUM(gmv) OVER (ORDER BY gmv DESC)/(SELECT total FROM tot)*100,2) AS `累计占比%`
FROM cat ORDER BY gmv DESC LIMIT 10;

-- 3) 品类畅销TOP-1商品：每个品类里销量最高的商品（ROW_NUMBER）
WITH base AS (
    SELECT
        COALESCE(cn.product_category_name_english,p.product_category_name) AS cname,
        oi.product_id,
        SUM(oi.price) AS gmv,
        COUNT(DISTINCT oi.order_id) AS orders
    FROM order_items oi
    JOIN products p USING (product_id)
    JOIN orders o ON o.order_id=oi.order_id AND o.order_status='delivered'
    LEFT JOIN category_name cn ON cn.product_category_name=p.product_category_name
    GROUP BY cn.product_category_name_english, p.product_category_name, oi.product_id
),
rnk AS (
    SELECT cname, product_id, ROUND(gmv,2) gmv, orders,
           ROW_NUMBER() OVER (PARTITION BY cname ORDER BY orders DESC) rn
    FROM base
)
SELECT cname `品类`, product_id `商品`, orders `订单量`, gmv `GMV`
FROM rnk WHERE rn<=1 ORDER BY gmv DESC LIMIT 15;

-- 4) 品类平均售价、均价运费、运费占售价比：判断哪些品类"运费敏感"
SELECT
    COALESCE(cn.product_category_name_english,p.product_category_name) AS `品类`,
    ROUND(AVG(oi.price),2)              AS `平均售价`,
    ROUND(AVG(oi.freight_value),2)      AS `平均运费`,
    ROUND(AVG(oi.freight_value)/NULLIF(AVG(oi.price),0)*100,1) AS `运费占售价%`
FROM order_items oi
JOIN products p USING (product_id)
JOIN orders o ON o.order_id=oi.order_id AND o.order_status='delivered'
LEFT JOIN category_name cn ON cn.product_category_name=p.product_category_name
GROUP BY cn.product_category_name_english, p.product_category_name
HAVING COUNT(DISTINCT oi.order_id) >= 50
ORDER BY `运费占售价%` DESC
LIMIT 15;

-- 5) 订单级：品类平均评分 vs 订单量（先对每个订单求该单平均分，避免同单多评拉水）
WITH order_rev AS (
    SELECT order_id, AVG(review_score) AS score FROM order_reviews GROUP BY order_id
)
SELECT
    COALESCE(cn.product_category_name_english, p.product_category_name, 'unknown') AS `品类`,
    COUNT(DISTINCT oi.order_id) AS `订单量`,
    ROUND(SUM(oi.price),2)      AS `GMV`,
    ROUND(AVG(r.score),2)       AS `平均评分`
FROM order_items oi
JOIN products p   USING (product_id)
JOIN orders o     ON o.order_id=oi.order_id AND o.order_status='delivered'
LEFT JOIN order_rev r ON r.order_id = oi.order_id
LEFT JOIN category_name cn ON cn.product_category_name = p.product_category_name
WHERE r.score IS NOT NULL
GROUP BY cn.product_category_name_english, p.product_category_name
HAVING COUNT(DISTINCT oi.order_id) >= 30
ORDER BY `订单量` DESC
LIMIT 20;