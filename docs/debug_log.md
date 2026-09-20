# 调试日志（debug_log.md）

> 本文件记录第二~四阶段运行过程中遇到的每个问题：**问题 → 原因 → 修改 → 验证结果**。
> 这是作品集里"真实工程师"最有力的证据之一。

---

## 问题清单与修复

### L-01 原项目 reviews 文件名不匹配（会导致导入中断）

- **问题**：按原项目流程运行，导入 `order_reviews` 时找不到文件。
- **原因**：原项目 `order_reviews_clean.py` 把清洗结果导出为 `order_reviews_dataset.csv`，但 `load_mysql.py` 读取的是 `order_reviews.csv`，名字不一致。
- **修改**：本项目重写清洗与导入脚本，统一命名为 `data/cleaned/order_reviews.csv`（见 `src/data_cleaning.py`）。
- **验证**：导入后 `SELECT COUNT(*) FROM order_reviews` = 98,410，与清洗输出一致。

### L-02 建表外键顺序错误（errno 150）

- **问题**：首次执行建表脚本报外键约束无法创建。
- **原因**：`order_items` 的外键引用了 `products`、`sellers`，但这两张表在我的 DDL 中排在 `order_items` 之后创建，MySQL 不允许外键指向尚不存在的表。
- **修改**：调整 DDL 顺序为 `category_name → sellers → products → customers → orders → order_items → order_payments → order_reviews`，先建被引用表。
- **验证**：建表成功，外键约束全部生效；导入后引用完整性检查 0 孤儿。

### L-03 SQL 列别名含 `%` 导致语法错误（1064）

- **问题**：`02_business_overview.sql` 的月度环比语句报语法错误 near `%`。
- **原因**：列别名直接写 `gmv_环比%`，`%` 无法作为未引用标识符。
- **修改**：将含 `%` 的别名用反引号包裹为 `` `环比%` ``。
- **验证**：执行成功，返回 23 个月度环比行。

### L-04 MySQL 无原生 `PERCENTILE_CONT` 分位函数

- **问题**：复购间隔中位数无法用 `PERCENTILE_CONT` 求得，报语法错误。
- **原因**：MySQL 8.x 不提供该分析函数。
- **修改**：改用窗口 `ROW_NUMBER()` + 总行数取中位（`rn = CEIL(cnt/2)`），见 `03_customer_analysis.sql`。
- **验证**：平均复购间隔 79.1 天，中位 29 天，符合分布预期（多数复购较快）。

### L-05 多表 JOIN 时 `USING(order_id)` 列歧义（1052）

- **问题**：04/07 中 `USING(order_id)` 报 "Column 'order_id' ambiguous"。
- **原因**：同一 FROM 上下文里 `order_items`、`orders`、reviews 子查询都含 `order_id`，未加限定时歧义。
- **修改**：相关评价子查询改为显式 `ON r.order_id = oi.order_id`（其余继续用 `USING` 保持简洁）。
- **验证**：07 两个相关查询恢复正常返回。

### L-06 引用不存在的列（1054）

- **问题**：`05_seller_analysis.sql` 报 `Unknown column 'rr.review_score'`。
- **原因**：子查询别名列名是 `sc`（`AVG(review_score) sc`），但外层写成了 `rr.review_score`。
- **修改**：改为 `rr.sc`。
- **验证**：卖家口碑分析正常返回。

---

## 数据口径核验（第四阶段结论）

| 检查项 | 结果 | 说明 |
|--------|------|------|
| 订单状态 | delivered 96,478 (97.02%) | canceled 625 / unavailable 609 等需在 GMV 口径中剔除 |
| 全部订单 GMV vs 仅交付 GMV | 13,591,643.70 vs 13,221,498.11 | 不筛状态会虚增约 2.8% 收入 |
| 全部订单数 vs 有效订单数 | 98,666 vs 96,478 | 虚增 2,188 单 |
| 支付 1:多 | 2,382 单有 2 次支付等（合计 ~2,961 单多笔） | 从 payment 表 SUM 会重复统计 GMV |
| 商品明细 1:多 | 112,650 明细 / 96,478 有效单 | JOIN 后必须 `COUNT(DISTINCT order_id)` |
| review_id 重复 | 去重 814 行 | 清洗期已 drop_duplicates |
| 同单多评 | 547 单 | 平均分须按 order_id 聚合后再算 |
| 主键重复 | 0 | orders/items/payments/reviews/products/sellers 均无 |
| 孤儿引用 | 0 | orders.customer_id 全部能在 customers 找到 |
| 价格/运费异常 | 0 个负数、0 缺失 | 数据归一良好 |

---

## 环境信息

- Windows + 本地 MySQL80（root 登录，端口 3306）
- Python 3.12.9 + 虚拟环境 `.venv`，pandas 2.x / numpy / pymysql / sqlalchemy
- 数据库 `ecommerce_bas`（UTF-8），8 张表全部 InnoDB + 外键