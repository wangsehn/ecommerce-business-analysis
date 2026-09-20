# 指标定义中心（metric_definition.md）

> 原则：先定义业务粒度，再写 SQL。任何指标都要能回答“分子/分母是什么、在哪一层聚合、连接后是否重复”。

---

## 1. 订单与金额

### 有效订单
- **定义**：`order_status='delivered'`。
- **当前规模**：96,478 单。
- **用途**：本作品集的商品 GMV、AOV、复购、履约分析默认使用 delivered 口径。

### 商品 GMV
- **定义**：有效订单的 `SUM(order_items.price)`，不含运费。
- **当前结果**：约 13.22M BRL。
- **注意**：这只是本项目定义的“商品成交额口径”，不是财务收入，也不是净 GMV（数据缺退款、补贴、成本）。

### 为什么不直接用 payment_value 当 GMV
- `order_payments.payment_value` 是支付记录金额；同一订单可以有多个 payment record。
- `payment_installments` 才是分期期数，`payment_sequential` 是支付记录顺序。
- 即便先按订单汇总 `payment_value`，它和“商品价 GMV”也不是同一口径，因此不能直接替代。

### AOV
- **定义**：商品 GMV / 有效订单数。
- 分母必须为 `COUNT(DISTINCT order_id)`，不能用 item 行数。

---

## 2. 客户与复购

### 唯一客户标识
- 客户级分析使用 `customer_unique_id`。
- `customer_id` 是订单级客户键；同一实际客户再次下单会产生新的 `customer_id`。
- 因此 96,096 应称为“`customer_unique_id` 去重客户数”，不能称为“注册用户”。

### 有有效购买的唯一客户
- **定义**：至少有 1 笔 delivered 订单的 `customer_unique_id`。
- **当前结果**：93,358。

### 复购客户 / 复购率
- **复购客户**：至少有 2 笔不同 delivered 订单的唯一客户。
- **当前结果**：2,801。
- **复购率**：2,801 / 93,358 = **3.00%**。
- **解释边界**：低复购是样本期交易结构事实；不能仅凭这一项断言平台“获客驱动”或解释复购低的原因。

### 复购间隔
- 用 `LAG(order_purchase_timestamp)` 计算同一 `customer_unique_id` 相邻两笔有效订单间隔。
- 当前结果：平均约 79.1 天、中位约 29 天。
- **业务使用**：29 天可作为二次购买触达实验的候选窗口，不代表已证明“30 天最优”。

### 月度复购留存（Purchase Retention）
- **定义**：同一首购月份客户，在第 N 个后置月再次出现 delivered 订单的人数 / cohort 首购人数。
- 这是**交易复购留存**，不是登录/活跃留存。
- 首购当月是基准期（100%）；解读应从后置月开始。
- 靠近数据窗口尾部的 cohort 后置观察期不足，必须谨慎比较。

---

## 3. 履约与物流

### 配送时长
- **定义**：`DATEDIFF(DATE(actual_delivery), DATE(purchase_timestamp))`。
- 仅对 delivered 且实际送达日期非空订单统计。

### 准时 / 超时
本项目统一采用**日粒度 SLA**：

```sql
准时：DATE(order_delivered_customer_date) <= DATE(order_estimated_delivery_date)
超时：DATE(order_delivered_customer_date) >  DATE(order_estimated_delivery_date)
```

采用日粒度是为了与“超时天数”的 `DATEDIFF` 分桶保持一致，并避免把“预计送达日当天晚于 00:00 到货”误判为超时。

> 旧版本曾混用 timestamp 比较与 DATEDIFF，导致准时率/超时率出现两套结果。该问题已在 `sql/06_logistics_analysis.sql` 修正。**旧的 8.11%、1.73 分等物流结论暂不作为公开作品集结论，需用更新后的 SQL 重跑后重新写入。**

### 卖家物流
- 必须先去重到 `seller_id + order_id` 粒度，再统计延迟率。
- 否则同一卖家在一单内多个 item 会让超时分子被重复累加。

---

## 4. 商品与卖家

### 品类 GMV / 订单量
- GMV：有效订单 item price 汇总。
- 订单量：`COUNT(DISTINCT order_id)`。

### 卖家梯队
- 按 delivered 订单商品 GMV 从高到低排序。
- 当前展示：前 2% = 头部，2%–20% = 腰部，其余 = 长尾。
- 当前结果显示前 20% 卖家贡献约 82% 商品 GMV。
- **解释边界**：这是供给 GMV 集中结构，不等于已经证明“经营风险”；风险还需要利润、卖家替代性、流失概率等数据验证。

### 卖家评分
- 先构造 `DISTINCT seller_id, order_id`，再连接订单级评分。
- 避免一单多 item 让同一评分重复加权。

---

## 5. 评分与支付

### 订单级评分
先对 `order_reviews` 按 `order_id` 聚合，再进入后续分析。

### 支付方式与评分
先去重到 `order_id + payment_type` 粒度，再比较评分，避免同一订单同支付类型的多记录重复。

### 价格档与评分
先把 delivered 订单 item 汇总成订单商品金额，再分档；不直接按 item price 给订单分组。

---

## 6. 当前可安全用于公开展示的核心结果

- delivered 有效订单：**96,478**
- 商品 GMV：**约 13.22M BRL**
- 有有效购买的唯一客户：**93,358**
- 复购客户：**2,801**
- 复购率：**3.00%**
- 复购间隔中位数：**约 29 天**
- 前 20% 卖家商品 GMV 占比：**约 82%**

物流相关数值将在统一日粒度 SLA 后重新生成再公开。
