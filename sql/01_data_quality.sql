-- ============================================================================
-- 01_data_quality.sql  ——  数据质量核验
-- ----------------------------------------------------------------------------
-- 业务问题：所有分析结论都建立在数据可信的前提上。先核验表结构、行数、缺失率、
--           重复主键、外键引用完整性，再进入业务分析。
-- 指标定义：
--   - 缺失率 = 某列 NULL / 总行数
--   - 重复主键 = 主键出现次数 > 1 的行是否剔净（reviews 已在清洗期按 review_id 去重 814 行）
--   - 引用完整性 = orders.customer_id 是否都能在 customers 中找到（外键是否有孤儿）
-- SQL思路：分块查询，输出可直接人对账的核验结果。
-- ============================================================================
USE ecommerce_bas;

-- 1) 各表行数（精确 COUNT）
SELECT 'customers' AS tbl, COUNT(*) AS rows_cnt FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'category_name', COUNT(*) FROM category_name;

-- 2) 主键唯一性：所有表主键不应重复
SELECT 'orders.order_id dup' AS check_item,
       COUNT(*) - COUNT(DISTINCT order_id) AS dup_cnt FROM orders
UNION ALL SELECT 'customers.customer_id dup', COUNT(*) - COUNT(DISTINCT customer_id) FROM customers
UNION ALL SELECT 'products.product_id dup', COUNT(*) - COUNT(DISTINCT product_id) FROM products
UNION ALL SELECT 'sellers.seller_id dup', COUNT(*) - COUNT(DISTINCT seller_id) FROM sellers
UNION ALL SELECT 'review.review_id dup', COUNT(*) - COUNT(DISTINCT review_id) FROM order_reviews;

-- 3) 订单状态分布：判断哪些状态属于"有效/成交/交付"
SELECT order_status,
       COUNT(*) AS order_cnt,
       ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 2) AS pct
FROM orders
GROUP BY order_status
ORDER BY order_cnt DESC;

-- 4) 关键列缺失率：orders 关键时间节点
SELECT
    ROUND(SUM(order_purchase_timestamp IS NULL) / COUNT(*) * 100, 2) AS purchase_null_pct,
    ROUND(SUM(order_approved_at IS NULL)      / COUNT(*) * 100, 2) AS approved_null_pct,
    ROUND(SUM(order_delivered_customer_date IS NULL) / COUNT(*) * 100, 2) AS delivered_null_pct,
    ROUND(SUM(order_estimated_delivery_date IS NULL)   / COUNT(*) * 100, 2) AS estimated_null_pct
FROM orders;

-- 5) 引用完整性：orders.customer_id 是否存在孤儿（结果应为 0）
SELECT COUNT(*) AS orphan_orders
FROM orders o
LEFT JOIN customers c USING (customer_id)
WHERE c.customer_id IS NULL;

-- 6) 支付次数分布：确认 payment 表 1:多结构（分期/多笔），
--    用于后续 GMV 统计必须先去重，避免重复求和
SELECT pay_cnt, COUNT(*) AS order_cnt
FROM (
    SELECT order_id, COUNT(*) AS pay_cnt
    FROM order_payments
    GROUP BY order_id
) t
GROUP BY pay_cnt
ORDER BY pay_cnt;

-- 7) 评分分布：确认 review_score（1~5）的有效性
SELECT review_score, COUNT(*) AS review_cnt
FROM order_reviews
WHERE review_score IS NOT NULL
GROUP BY review_score
ORDER BY review_score;

-- 8) 价格/运费异常：负数或缺失（应无异常）
SELECT
    SUM(price < 0) AS price_neg,
    SUM(price IS NULL) AS price_null,
    SUM(freight_value < 0) AS freight_neg,
    SUM(freight_value IS NULL) AS freight_null
FROM order_items;