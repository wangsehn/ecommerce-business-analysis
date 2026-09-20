-- ============================================================================
-- 07_review_analysis.sql  ——  评价与体验分析（支撑页面 4 与业务洞察）
-- ----------------------------------------------------------------------------
-- 业务问题：评分整体如何？差评集中在哪（支付/品类/价格段）？评价与业务动作如何关联。
-- 口径：评价用 order_id 聚合后的平均分/一票（避免同单多评拉水）。
-- ============================================================================
USE ecommerce_bas;

-- 1) 整体评分分布与差评率（差评=评分<=2）
SELECT
    COUNT(*) AS `评价订单`,
    ROUND(AVG(sc),2) AS `平均分`,
    SUM(sc<=2) AS `差评单`,
    ROUND(SUM(sc<=2)/COUNT(*)*100,2) AS `差评率%`,
    SUM(sc<=1) AS `一星单`
FROM (SELECT order_id, AVG(review_score) sc FROM order_reviews GROUP BY order_id) r;

-- 2) 价格段 vs 评分：低价高量与高价低量评分如何（帮助"体验"主题归因）
WITH oi AS (
    SELECT oi.order_id, oi.price
    FROM order_items oi
    JOIN orders o ON o.order_id=oi.order_id AND o.order_status='delivered'
),
r AS (SELECT order_id, AVG(review_score) sc FROM order_reviews GROUP BY order_id)
SELECT
    CASE WHEN oi.price<50 THEN '<50'
         WHEN oi.price<100 THEN '50-100'
         WHEN oi.price<200 THEN '100-200'
         WHEN oi.price<400 THEN '200-400'
         ELSE '>400' END AS `价格档`,
    COUNT(DISTINCT oi.order_id) AS `订单量`,
    ROUND(AVG(r.sc),2) AS `平均评分`
FROM oi LEFT JOIN r USING (order_id)
WHERE r.sc IS NOT NULL
GROUP BY `价格档`
ORDER BY MIN(oi.price);

-- 3) 支付方式 vs 评分：分期多次支付是否伴随较差体验（间接信号）
SELECT
    op.payment_type AS `支付方式`,
    COUNT(DISTINCT op.order_id) AS `订单量`,
    ROUND(AVG(r.sc),2) AS `平均评分`,
    ROUND(SUM(r.sc<=2)/COUNT(DISTINCT op.order_id)*100,2) AS `差评率%`
FROM order_payments op
LEFT JOIN (SELECT order_id, AVG(review_score) sc FROM order_reviews GROUP BY order_id) r USING (order_id)
WHERE r.sc IS NOT NULL
GROUP BY op.payment_type
ORDER BY `订单量` DESC;

-- 4) 目标对比：评分 Top vs Bottom 品类的体验差异（为选品建议提供素材）
SELECT
    COALESCE(cn.product_category_name_english,p.product_category_name,'unknown') AS `品类`,
    COUNT(DISTINCT oi.order_id) AS `订单量`,
    ROUND(AVG(r.sc),2) AS `平均评分`
FROM order_items oi
JOIN products p USING (product_id)
JOIN orders o ON o.order_id=oi.order_id AND o.order_status='delivered'
LEFT JOIN category_name cn ON cn.product_category_name=p.product_category_name
LEFT JOIN (SELECT order_id, AVG(review_score) sc FROM order_reviews GROUP BY order_id) r ON r.order_id=oi.order_id
WHERE r.sc IS NOT NULL
GROUP BY cn.product_category_name_english, p.product_category_name
HAVING COUNT(DISTINCT oi.order_id)>=50
ORDER BY `平均评分` ASC
LIMIT 15;