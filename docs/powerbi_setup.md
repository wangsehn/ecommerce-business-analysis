# Power BI 作品集复现指南（powerbi_setup.md）

> 说明：`.pbix` 是 Power BI Desktop 的二进制专有格式，无法用脚本直接生成。
> 本作品集交付了两部分可视化成果：
>   1. `assets/dashboard/index.html` —— 用真实数据渲染的 4 页交互式仪表盘（当前已有的可直接展示版本）。
>   2. 本指南 —— 在 Power BI Desktop 里约 1 小时内重建出真正 `.pbix` 的完整步骤、图表类型与 DAX 度量。
> 二者内容与结论完全一致，只是载体不同。

---

## 一、数据源接入

1. 打开 Power BI Desktop → 获取数据 → MySQL 数据库。
2. 服务器 `127.0.0.1`，数据库 `ecommerce_bas`，用户名 `root`，密码（你的本地密码）。
3. 勾选导入 8 张业务表。
4. 在"关系"视图确认外键关系已自动或手工建立：
   `customers ↔ orders ↔ order_items ↔ {products, sellers}`，`orders ↔ order_payments/order_reviews`。

---

## 二、推荐使用的度量（DAX，新建度量表）

建议新建一个"度量表"统一存放，便于管理。

```
GMV(有效) = CALCULATE(SUM(order_items[price]), orders[order_status]="delivered")

有效订单数 = CALCULATE(DISTINCTCOUNT(order_items[order_id]), orders[order_status]="delivered")

APP客单价 = DIVIDE([GMV(有效)], [有效订单数])

有效运费 = CALCULATE(SUM(order_items[freight_value]), orders[order_status]="delivered")

有购买用户 = CALCULATE(DISTINCTCOUNT(customers[customer_unique_id]),
                     FILTER(orders, orders[order_status]="delivered"))

复购用户 = CALCULATE(DISTINCTCOUNT(orders[customer_id]), orders[order_status]="delivered",
                  customers[customer_unique_id] IN /* 至少2单的用户集合，见下方明细 */ )
```

> **建议不要**把 GMV 直接从 `order_payments` 取（分期多次支付会重复，见 `docs/debug_log.md` L-… 数据口径）。

**复购率更稳妥的实现**（用虚拟表）：

```
复购率 =
VAR 购买用户 = CALCULATETABLE(DISTINCT(customers[customer_unique_id]),
                 FILTER(orders, orders[order_status]="delivered"))
VAR 复购用户 =
  COUNTROWS(
    FILTER(ADDCOLUMNS(购买用户,"单数",
       CALCULATE(DISTINCTCOUNT(orders[order_id]),
                 FILTER(orders, orders[order_status]="delivered"))
    ), [单数]>=2)
  )
RETURN DIVIDE(复购用户, COUNTROWS(购买用户))
```

**超时率**倒在 orders 上：
```
配送天数 = DATEDIFF(orders[order_purchase_timestamp], orders[order_delivered_customer_date], DAY)
是否超时 = IF(orders[order_delivered_customer_date] > orders[order_estimated_delivery_date], 1, 0)

超时率% =
DIVIDE(
  CALCULATE(SUM(orders[是否超时]),
            orders[order_status]="delivered",
            orders[order_delivered_customer_date]<>BLANK(),
            orders[order_estimated_delivery_date]<>BLANK()),
  CALCULATE(COUNTROWS(orders), orders[order_status]="delivered",
            orders[order_delivered_customer_date]<>BLANK(),
            orders[order_estimated_delivery_date]<>BLANK())
)
```

**订单均分（避免同单多评拉水）**：建议用 DAX 生成表或直接在 SQL 层做一张"订单级评分"表再导入，Power BI 中 `AVERAGE(order_reviews[review_score])` 会多算。推荐导入 `data/cleaned` 之外另加一张透视视图。

---

## 三、4 页布局模板

| 页 | 顶部 KPI | 主图表区 |
|----|---------|---------|
| **Page1 经营总览** | GMV、有效订单、AOV、运费总额 | ① 月度GMV=柱状+订单量=折线（双轴）；② 品类GMV=横向条形；③ 地区GMV=地图或条形 |
| **Page2 用户价值** | 复购率、复购用户、有购买用户 | ① 购买频次=柱状；② 每月新增用户=折线；③ Cohort=矩阵(行=首购月,列=第N期,值=留存率%) |
| **Page3 商品与卖家** | Top品类、头部卖家GMV占比 | ① 卖家梯队=堆叠条形；② 品类GMV vs订单=散点；③ Top商品=表 |
| **Page4 物流与体验** | 平均配送、准时率、超时率、准/超时均分 | ① 配送时长档位 vs 平均评分=柱状(双轴评分)；② 地区超时率=条形；③ 配送时长仪表 |

**视觉规范**：统一配色（本仪表盘用 #4C78A8 主蓝 / #E45756 警示橙 / #59A14F 增长绿），单页不超过 5 个图，KPI 卡片在最上，字号层级清晰，中文标题。

---

## 四、直接导出的成品

- `assets/dashboard/index.html`：4 页交互式仪表盘（真实数据，可直接打开演示）。
- `assets/dashboard/*.png`：4 页所有图表的高清图片，可直接用于简历/文档。
- `assets/eda/*.png`：探索性分析图表。

如需把上述图片二次加工/替换，可运行（在项目根目录）：
```bash
.venv\Scripts\python.exe scripts_temp_dashboard.py
```