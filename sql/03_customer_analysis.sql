-- ============================================================================
-- 03_customer_analysis.sql  ——  用户价值分析（页面 2 的数据层）
-- ----------------------------------------------------------------------------
-- 业务问题：用户是平台的长期增长引擎。要回答——新增速度、谁会复购、复购间隔多长、
--           老客价值多大、应给谁做运营。
-- 口径关键点（区别于原项目，务必可解释）：
--   * 用户级一律用 customer_unique_id（客户ID customer_id 是"订单级"，
--     一个真实用户或多个订单对应多个 customer_id，用它会重复数人数）。
--   * 有效订单 = order_status='delivered'；购买行为只统计有效订单。
--   * 复购 = 一个 unique_id 在 >=2 个不同有效订单中出现。
--   * 留存率 = 某首购月份用户中，在第 N 后置月份仍有有效购买的比例。
-- ============================================================================
USE ecommerce_bas;

-- 1) 真实用户数 vs 订单客户数：证明为什么用 customer_unique_id（答面试的"为什么"）
SELECT
    COUNT(DISTINCT customer_id)        AS `customer_id维度数量`,
    COUNT(DISTINCT customer_unique_id) AS `真实用户数`,
    COUNT(*)                           AS `customers表行数`
FROM customers;

-- 2) 用户购买频次分布：多少用户只买一次、买两次……
SELECT
    order_cnt AS `购买订单数`,
    COUNT(*)  AS `用户数`,
    ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) AS `占比%`
FROM (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_cnt
    FROM customers c
    JOIN orders o ON o.customer_id=c.customer_id AND o.order_status='delivered'
    GROUP BY c.customer_unique_id
) t
GROUP BY order_cnt
ORDER BY order_cnt;

-- 3) 整体复购率：至少买过 1 单的用户中，>=2 单的比例
WITH user_orders AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS n
    FROM customers c
    JOIN orders o ON o.customer_id=c.customer_id AND o.order_status='delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*)                                        AS `有购买用户数`,
    SUM(CASE WHEN n>=2 THEN 1 ELSE 0 END)           AS `复购用户数`,
    ROUND(SUM(CASE WHEN n>=2 THEN 1 ELSE 0 END)/COUNT(*)*100, 2) AS `复购率%`
FROM user_orders;

-- 4) 每月新增用户 & 当季/当月活跃：判断新增是否可持续
WITH first_order AS (
    SELECT c.customer_unique_id,
           DATE_FORMAT(MIN(o.order_purchase_timestamp),'%Y-%m') AS first_ym
    FROM customers c
    JOIN orders o ON o.customer_id=c.customer_id AND o.order_status='delivered'
    GROUP BY c.customer_unique_id
)
SELECT first_ym AS `首购月份`, COUNT(*) AS `新增用户`
FROM first_order
GROUP BY first_ym
ORDER BY first_ym;

-- 5) 复购间隔统计：相邻两次购买间隔的平均/中位天数（用窗口 LAG 求相邻间隔，
--    比"首末单跨度"更贴近真实的复购周期；MySQL 8 无原生分位函数，用 ROW_NUMBER 求中位）
WITH gaps AS (
    SELECT c.customer_unique_id,
           DATEDIFF(o.order_purchase_timestamp,
                    LAG(o.order_purchase_timestamp) OVER (
                        PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp
                    )) AS gap_days
    FROM customers c
    JOIN orders o ON o.customer_id=c.customer_id AND o.order_status='delivered'
),
ranked AS (
    SELECT gap_days,
           ROW_NUMBER() OVER (ORDER BY gap_days) AS rn,
           COUNT(*) OVER () AS cnt
    FROM gaps WHERE gap_days IS NOT NULL
)
SELECT ROUND(AVG(gap_days),1) AS `平均间隔(天)`,
       (SELECT ROUND(gap_days,0) FROM ranked WHERE rn = CEIL(cnt/2)) AS `中位间隔(天)`
FROM gaps WHERE gap_days IS NOT NULL;

-- 7) Cohort 留存：按首购月份 × 后置月份，算留存用户数与留存率%
WITH user_months AS (
    SELECT c.customer_unique_id,
           DATE_FORMAT(o.order_purchase_timestamp,'%Y-%m') AS purchase_ym,
           DATE_FORMAT(MIN(o.order_purchase_timestamp) OVER (
               PARTITION BY c.customer_unique_id
           ),'%Y-%m') AS first_ym
    FROM customers c
    JOIN orders o ON o.customer_id=c.customer_id AND o.order_status='delivered'
),
timeline AS (
    SELECT first_ym, purchase_ym,
           COUNT(DISTINCT customer_unique_id) AS users
    FROM user_months
    GROUP BY first_ym, purchase_ym
),
cohort_size AS (
    SELECT first_ym, MAX(CASE WHEN purchase_ym=first_ym THEN users END) AS size
    FROM timeline GROUP BY first_ym
)
SELECT
    t.first_ym AS `首购月份`,
    t.purchase_ym AS `购买月份`,
    TIMESTAMPDIFF(MONTH, CONCAT(t.first_ym,'-01'), CONCAT(t.purchase_ym,'-01')) + 1 AS `后置月/期`,
    t.users AS `留存用户`,
    cs.size AS `首购用户`,
    ROUND(t.users / cs.size * 100, 2) AS `留存率%`
FROM timeline t
JOIN cohort_size cs USING (first_ym)
ORDER BY t.first_ym, t.purchase_ym;

-- 8) RFM 分层：R=距最近购买天数, F=购买单数, M=累计GMV，用跨分位数打标
WITH user_rfm AS (
    SELECT c.customer_unique_id AS uid,
        DATEDIFF((SELECT MAX(order_purchase_timestamp) FROM orders WHERE order_status='delivered'),
                 MAX(o.order_purchase_timestamp)) AS R_recency_days,
        COUNT(DISTINCT o.order_id) AS F_freq,
        ROUND(SUM(oi.price),2) AS M_monetary
    FROM customers c
    JOIN orders o ON o.customer_id=c.customer_id AND o.order_status='delivered'
    LEFT JOIN order_items oi USING (order_id)
    GROUP BY c.customer_unique_id
),
scored AS (
    SELECT uid, R_recency_days, F_freq, M_monetary,
        ROW_NUMBER() OVER (ORDER BY R_recency_days ASC) AS r_asc_n,
        ROW_NUMBER() OVER (ORDER BY F_freq DESC)          AS f_dsc_n,
        ROW_NUMBER() OVER (ORDER BY M_monetary DESC)      AS m_dsc_n,
        COUNT(*) OVER () AS total
    FROM user_rfm
)
SELECT uid AS `用户`,
       R_recency_days                          AS `R_最近购买天数`,
       F_freq                                  AS `F_购买单数`,
       M_monetary                              AS `M_累计GMV`,
       CASE WHEN r_asc_n <= total*0.3   THEN '近' ELSE '远' END AS `R档`,
       CASE WHEN f_dsc_n <= total*0.3   THEN '高' ELSE '低' END AS `F档`,
       CASE WHEN m_dsc_n <= total*0.3   THEN '高' ELSE '低' END AS `M档`
FROM scored
ORDER BY M_monetary DESC
LIMIT 20;