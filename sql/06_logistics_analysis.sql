-- ============================================================================
-- 06_logistics_analysis.sql  ——  物流与履约分析（页面 4 数据层）
-- ----------------------------------------------------------------------------
-- 业务问题：配送到底快不快、准不准？哪里最慢（地区/卖家）？物流变慢会不会拉低评分？
-- 定义（统一口径，见 docs/metric_definition.md）：
--   - 配送时长(天) = DATEDIFF(delivered_customer_date, purchase_timestamp)
--   - 准时 = 实际送达 <= 预计送达日（估算到货时间）
--   - 超时 = 实际送达晚于预计送达
--   - 只对 order_status='delivered' 且有送达日期/预估日期的订单计算。
-- ============================================================================
USE ecommerce_bas;

-- 1) 整体配送时长分布：平均/中位，看普遍时效
WITH t AS (
    SELECT DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS days
    FROM orders o
    WHERE o.order_status='delivered' AND o.order_delivered_customer_date IS NOT NULL
)
SELECT ROUND(AVG(days),1) AS `平均配送天数`,
       ROUND((SELECT days FROM (SELECT days,
               ROW_NUMBER() OVER (ORDER BY days) rn, COUNT(*) OVER() cnt FROM t) x
             WHERE rn=CEIL(cnt/2)),1) AS `中位配送天数`,
       COUNT(*) AS `已配送订单`
FROM t;

-- 2) 准时率 / 超时率：整体口径
SELECT
    COUNT(*) AS `已配送订单`,
    SUM(order_delivered_customer_date <= order_estimated_delivery_date) AS `准时单`,
    SUM(order_delivered_customer_date >  order_estimated_delivery_date) AS `超时单`,
    ROUND(SUM(order_delivered_customer_date > order_estimated_delivery_date)/COUNT(*)*100,2) AS `超时率%`,
    ROUND(SUM(order_delivered_customer_date <= order_estimated_delivery_date)/COUNT(*)*100,2) AS `准时率%`
FROM orders
WHERE order_status='delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;

-- 3) 超时天数分布：超时多少天（扩散到 1-3/4-7/7+ 分桶）
SELECT
    CASE
        WHEN days<=0 THEN '准时'
        WHEN days<=3 THEN '超时1-3天'
        WHEN days<=7 THEN '超时4-7天'
        ELSE '超时7天以上' END AS `档位`,
    COUNT(*) AS `订单数`,
    ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) AS `占比%`
FROM (
    SELECT DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) AS days
    FROM orders
    WHERE order_status='delivered' AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
) t
GROUP BY `档位`
ORDER BY MIN(days);

-- 4) 各地区物流表现：超时率 + 平均配送时长（识别履约压力大的地区）
SELECT
    c.customer_state AS `州`,
    COUNT(*) AS `配送订单`,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)),1) AS `平均配送天数`,
    ROUND(SUM(o.order_delivered_customer_date > o.order_estimated_delivery_date)/COUNT(*)*100,2) AS `超时率%`
FROM orders o
JOIN customers c USING (customer_id)
WHERE o.order_status='delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY c.customer_state
HAVING COUNT(*) >= 200
ORDER BY `超时率%` DESC
LIMIT 12;

-- 5) 卖家端物流表现：哪些卖家履约最差（延迟率高）
SELECT
    oi.seller_id AS `卖家`,
    COUNT(DISTINCT oi.order_id) AS `订单量`,
    ROUND(SUM(o.order_delivered_customer_date > o.order_estimated_delivery_date)/COUNT(DISTINCT oi.order_id)*100,2) AS `延迟率%`,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)),1) AS `平均配送天数`
FROM order_items oi
JOIN orders o ON o.order_id=oi.order_id AND o.order_status='delivered'
  AND o.order_delivered_customer_date IS NOT NULL AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY oi.seller_id
HAVING COUNT(DISTINCT oi.order_id) >= 20
ORDER BY `延迟率%` DESC
LIMIT 12;

-- 6) 配送时长 vs 评分：量化"慢配送影响体验"（物联想到评分栏）
WITH dlv AS (
    SELECT o.order_id,
           DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS days,
           CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END AS is_late,
           r.sc AS score
    FROM orders o
    LEFT JOIN (SELECT order_id, AVG(review_score) sc FROM order_reviews GROUP BY order_id) r USING (order_id)
    WHERE o.order_status='delivered' AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL AND r.sc IS NOT NULL
)
SELECT
    CASE WHEN days<=3 THEN '<=3天' WHEN days<=7 THEN '4-7天'
         WHEN days<=10 THEN '8-10天' WHEN days<=15 THEN '11-15天' ELSE '>15天' END AS `配送时长档`,
    COUNT(*) AS `订单数`,
    ROUND(AVG(score),2) AS `平均评分`,
    SUM(is_late) AS `超时单`,
    ROUND(SUM(is_late)/COUNT(*)*100,2) AS `超时率%`
FROM dlv
GROUP BY `配送时长档`
ORDER BY MIN(days);

-- 7) 超时对评分的直接影响：准时 vs 超时订单均分对比
SELECT
    CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN '超时' ELSE '准时' END AS `履约`,
    COUNT(*) AS `订单数`,
    ROUND(AVG(r.sc),2) AS `平均评分`
FROM orders o
LEFT JOIN (SELECT order_id, AVG(review_score) sc FROM order_reviews GROUP BY order_id) r USING (order_id)
WHERE o.order_status='delivered' AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL AND r.sc IS NOT NULL
GROUP BY `履约`;