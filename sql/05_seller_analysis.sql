-- ============================================================================
-- 05_seller_analysis.sql  ——  卖家分析（页面 3 数据层之二）
-- ----------------------------------------------------------------------------
-- 业务问题：平台卖家高度分散还是集中？少数头部卖家是否贡献了大部分 GMV（依赖风险）？
--           腰部/长尾卖家怎么分层？是否存在"GMV 高但评分低"的危险卖家（结构风险）。
-- 分层口径（基于分布而非拍脑袋阈值）：
--   - 头部：GMV 累计占比达 ~80% 的那批卖家中的前列
--   - 简化分层：按 GMV 从高到低，排名前 5% 叫头部、5%~20% 叫腰部、其余长尾。
--   * 若一个卖家被取消单比例高、差评高但 GMV 高，需重点排查。
-- ============================================================================
USE ecommerce_bas;

-- 1) 卖家 GMV 集中度：结合 SUM OVER + 排名，看 top 卖家撑起多大 GMV
WITH seller_gmv AS (
    SELECT s.seller_id,
           SUM(oi.price) AS gmv,
           COUNT(DISTINCT oi.order_id) AS orders
    FROM sellers s
    JOIN order_items oi USING (seller_id)
    JOIN orders o ON o.order_id=oi.order_id AND o.order_status='delivered'
    GROUP BY s.seller_id
),
tot AS (SELECT SUM(gmv) total FROM seller_gmv)
SELECT seller_id `卖家`,
       ROUND(gmv,2) `GMV`,
       ROUND(gmv/(SELECT total FROM tot)*100,2) `占GMV%`,
       ROUND(SUM(gmv) OVER (ORDER BY gmv DESC)/(SELECT total FROM tot)*100,2) `累计GMV%`
FROM seller_gmv ORDER BY gmv DESC LIMIT 15;

-- 2) 卖家分层：头部/腰部/长尾规模与 GMV 贡献（用 NTILE/百分位简化）
WITH sgm AS (
    SELECT s.seller_id,
           SUM(oi.price) AS gmv,
           COUNT(DISTINCT oi.order_id) AS orders,
           ROW_NUMBER() OVER (ORDER BY SUM(oi.price) DESC) AS rn,
           COUNT(*) OVER () AS total
    FROM sellers s
    JOIN order_items oi USING (seller_id)
    JOIN orders o ON o.order_id=oi.order_id AND o.order_status='delivered'
    GROUP BY s.seller_id
)
SELECT
    CASE WHEN rn <= total*0.02 THEN '头部(前2%)'
         WHEN rn <= total*0.20 THEN '腰部(2-20%)'
         ELSE '长尾' END AS `梯队`,
    COUNT(*) AS `卖家数`,
    ROUND(SUM(gmv),2) AS `梯队GMV`,
    ROUND(SUM(gmv)/SUM(SUM(gmv)) OVER()*100,2) AS `占GMV%`
FROM sgm
GROUP BY `梯队`
ORDER BY `占GMV%` DESC;

-- 3) 卖家销售频次结构：多少卖家是"偶尔才卖出"的长尾
WITH sgm AS (
    SELECT s.seller_id, COUNT(DISTINCT oi.order_id) AS orders
    FROM sellers s JOIN order_items oi USING (seller_id)
    JOIN orders o ON o.order_id=oi.order_id AND o.order_status='delivered'
    GROUP BY s.seller_id
)
SELECT
    CASE WHEN orders=1 THEN '1单'
         WHEN orders<=5 THEN '2-5单'
         WHEN orders<=20 THEN '6-20单'
         ELSE '20+单' END AS `累计下单档位`,
    COUNT(*) AS `卖家数`,
    ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) AS `占比%`
FROM sgm GROUP BY `累计下单档位` ORDER BY `累计下单档位`;

-- 4) 高GMV但低评分卖家：结构风险清单（GMV 高但平均评分低）
WITH s AS (
    SELECT oi.seller_id,
           ROUND(SUM(oi.price),2) AS gmv,
           COUNT(DISTINCT oi.order_id) AS orders
    FROM order_items oi
    JOIN orders o ON o.order_id=oi.order_id AND o.order_status='delivered'
    GROUP BY oi.seller_id
),
r AS (
    SELECT oi.seller_id, ROUND(AVG(rr.sc),2) AS avg_score, COUNT(*) AS n_review
    FROM order_items oi
    JOIN (SELECT order_id, AVG(review_score) sc FROM order_reviews GROUP BY order_id) rr ON rr.order_id=oi.order_id
    GROUP BY oi.seller_id
)
SELECT s.seller_id `卖家`,
       s.gmv `GMV`,
       s.orders `订单量`,
       r.avg_score `平均评分`,
       r.n_review `评价数`,
       CASE WHEN r.avg_score<=4 AND s.gmv>30000 THEN '⚠风险(高GMV低分)'
            ELSE '正常' END AS `标记`
FROM s LEFT JOIN r USING (seller_id)
WHERE s.orders >= 10 AND r.avg_score IS NOT NULL
ORDER BY s.gmv DESC
LIMIT 25;

-- 5) 卖家地域分布：卖家集中在哪些州（供应端地理风险）
SELECT s.seller_state `州`,
       COUNT(*) `卖家数`,
       ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) `占比%`
FROM sellers s GROUP BY s.seller_state ORDER BY `卖家数` DESC LIMIT 12;