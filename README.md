# 电商经营与用户价值数据分析

基于巴西 Olist 电商公开数据集的**独立数据分析作品集**，覆盖「数据清洗 → MySQL 建模 → SQL 经营/用户/商品/卖家/物流分析 → 可视化 Dashboard → 业务洞察」全流程。

> 面向读者：招聘 HR 与数据分析面试官。你可以快速看到**数据规模、指标体系、分析框架、核心发现、业务建议与项目局限**，并据此判断候选人的业务理解与工程能力。

---

## 一、项目背景

求职数据分析 / 电商数据分析 / 经营分析 / 数据运营方向，需要一套能**经得起面试追问**的完整作品集。本项目不满足于"跑通开源项目"，而是：
- 从原始数据做起，先审计并修正一个教学型开源框架的指标口径错误；
- 重新设计面向管理层的业务分析框架；
- 每个指标口径、每条 SQL、每张图都能讲清楚"为什么"。

目标技术栈：**Python · Pandas · MySQL · SQL · Power BI · Git**。重点在数据清洗、建模、SQL 业务分析、指标体系与可视化，不刻意堆机器学习。

---

## 二、数据来源

- **数据集**：[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)（Kaggle 官方公开数据集）。
- **范围**：巴西一家电商平台，时间 2016-09 ~ 2018-08。
- **获取**：本仓库不包含原始大文件，按 `data/README.md` 说明下载后放 `data/raw/`。

---

## 三、数据规模（实测）

| 表 | 行数 | 说明 |
|----|------|------|
| customers | 99,441 | 客户（真实用户去重 96,096） |
| orders | 99,441 | 订单（有效 delivered 96,478） |
| order_items | 112,650 | 订单商品明细 |
| order_payments | 103,886 | 支付记录（含分期多笔） |
| order_reviews | 98,410 | 评价（review_id 去重后） |
| products | 32,951 | 商品 |
| sellers | 3,095 | 卖家 |
| category_name | 71 | 品类翻译 |

**核心规模结论**：约 **9.9 万订单、9.6 万真实用户、3.3 万商品、3,095 卖家**；有效订单 GMV 约 **1,322 万 BRL**，客单价 137。

---

## 四、技术栈与工程

- **Python 3.12 + Pandas/NumPy/Matplotlib**：数据清洗、质量检查、EDA。
- **MySQL 8**：多表建模 + 全部业务 SQL。
- **SQL**：7 个主题文件，30+ 条业务 SQL，含 CTE、子查询、窗口函数（ROW_NUMBER / RANK / LAG / SUM·AVG OVER / PARTITION BY）。
- **Power BI**：4 页 Dashboard（本仓库提供真实数据渲染的 HTML 版 + Power BI 复现指南）。

---

## 五、数据模型（ER）

```text
customers ──1:N──> orders ──1:N──> order_items ──N:1──> products ──N:1──> category_name
                                      │
                                      └──N:1──> sellers
orders ──1:N──> order_payments
orders ──1:N──> order_reviews
```

多表关系要点（作品集关键卖点）：
- `customers.customer_id`（订单维度）一对多 → orders；`customer_unique_id` 才是真实用户。
- 一单多商品明细（JOIN 后须 `COUNT(DISTINCT order_id)`）。
- 支付表多笔（直接 SUM 会重复统计 GMV）。
- 评价表同单多评（均分按 order_id 聚合）。

---

## 六、指标体系（核心定义）

| 指标 | 定义 | 值 |
|------|------|----|
| 有效订单 | order_status='delivered' | 96,478 |
| GMV | 有效订单商品售价合计，不含运费 | 13,221,498 BRL |
| AOV 客单价 | GMV / 有效订单数 | 137.04 |
| 用户 | customer_unique_id 去重 | 96,096 |
| 有购买/复购用户 | 至少1单 / 至少2单 | 93,358 / 2,801 |
| 复购率 | 复购用户 / 有购买用户 | **3.00%** |
| 复购间隔 | 相邻两单间隔（LAG 计算） | 平均79天 / 中位29天 |
| 平均配送天数 | 下单→送达 | 12.5（中位10） |
| 准时率 / 超时率 | 实际送达≤预计 | 91.89% / **8.11%** |
| 平均评分 | 订单级评价均分 | 4.09（差评率14.61%） |

完整口径与"为什么这样定义"见 [docs/metric_definition.md](docs/metric_definition.md)。

---

## 七、分析过程（框架）

管理层追问 → 四主题：
- **A. 经营总览**：GMV/订单/客单价、月度趋势与环比、地区/品类结构。
- **B. 用户价值**：新增用户、复购率、频次、复购间隔、**Cohort 留存**、**RFM 分层**。
- **C. 商品与卖家**：品类 GMV/订单、GMV 集中度、运费敏感、卖家梯队、低分高 GMV 卖家风险。
- **D. 物流与体验**：配送时长、准时率、超时率、**物流→评分传导**、地区/卖家履约表现。

框架文档见 [docs/analysis_framework.md](docs/analysis_framework.md)，全量 SQL 见 `sql/`，报告见 [docs/analysis_report.md](docs/analysis_report.md)。

---

## 八、Dashboard

带真实数据的 4 页交互式仪表盘：`assets/dashboard/index.html`（直接用浏览器打开）。

| 页面 | 主题 | 关键结论 |
|------|------|---------|
| Page1 经营总览 | GMV/订单/客单价、月度趋势、品类/地区 | 增长驱动型平台 |
| Page2 用户价值 | 新增、复购、频次、Cohort、RFM | 复购率仅 3% |
| Page3 商品与卖家 | 品类、卖家梯队、货架结构 | 头部依赖 82% |
| Page4 物流与体验 | 配送、准时率、地区、评分关联 | 超时单均分降 1.7 分 |

Power BI 使用本数据建模的步骤、图表类型与 DAX 度量见 [docs/powerbi_setup.md](docs/powerbi_setup.md)。

---

## 九、核心发现（Top 关键结论，详见报告）

1. **复购是最大短板**：复购率仅 3.00%，97% 用户只买 1 单；Cohort 首期留存低 → 平台是"获客驱动"而非"留存驱动"。
2. **口径差 2.8%**：不筛交付状态会让 GMV 虚增约 2.8%、订单虚增 2,188 单。
3. **物流=体验放大器**：超时单均分 2.57 vs 准时单 4.30，差 1.73 分；配送>15天评分仅 3.60。
4. **北部州履约重灾**：AL/MA/PI/CE 超时率 15-24%、配送 19-24 天，远超平均。
5. **供给侧集中**：头部前2%卖家占 GMV 36%，前20%占约82%，80%长尾卖家仅贡献 17.7%。
6. **支付单一且与评分无关**：信用卡主导，支付方式不是体验分化解释变量。

---

## 十、业务建议（摘要）

- 从"首单→二单"和会员体系切入提升复购（性价比高于持续拉新）。
- 改善北部州与高延迟卖家履约，修复体验即修复口碑与留存。
- 平衡供给侧：清理零活跃长尾卖家、扶持腰部。
- 固定标准指标口径与数据质量检查，防止 GMV/复购被误算。

---

## 十一、项目局限（诚实声明）

- 结论多为**相关/可能**，无因果证明（无对照实验、无混淆控制）。
- 缺用户画像、营销渠道、点击、退款等字段，无法做深归因。
- 数据窗口约 2 年，尾部月份 cohort 无后置观察。
- 数据代表单一巴西平台，不可直接外推。

---

## 十二、如何运行（复现）

```bash
# 1) 准备数据：按 data/README.md 下载 Olist 原始 csv 到 data/raw/

# 2) 虚拟环境与依赖
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt     # Windows
source .venv/bin/pip install -r requirements.txt             # macOS/Linux

# 3) 数据清洗 -> data/cleaned/
.venv\Scripts\python src/data_cleaning.py

# 4) 建库建表导入 MySQL（库 ecommerce_bas；设环境变量 MYSQL_PWD 为你的root密码）
$env:MYSQL_PWD='你的密码'; .venv\Scripts\python src/load_mysql.py

# 5) 按顺序执行 sql/ 下的分析脚本（01-07）
# 6) 打开 notebooks/exploratory_analysis.ipynb 看 EDA
# 7) 用浏览器打开 assets/dashboard/index.html 看仪表盘；或用 Power BI Desktop 按 docs/powerbi_setup.md 重建 .pbix
```

---

## 十三、目录结构

```text
ecommerce-business-analysis/
├── README.md
├── requirements.txt
├── data/
│   ├── raw/                  # 原始数据（gitignore，按 data/README 下载）
│   ├── cleaned/              # 清洗后数据（生成）
│   └── README.md
├── src/
│   ├── data_cleaning.py      # 清洗
│   └── load_mysql.py         # 建库/建表/导入 MySQL
├── sql/
│   ├── 01_data_quality.sql
│   ├── 02_business_overview.sql
│   ├── 03_customer_analysis.sql
│   ├── 04_product_analysis.sql
│   ├── 05_seller_analysis.sql
│   ├── 06_logistics_analysis.sql
│   └── 07_review_analysis.sql
├── notebooks/
│   └── exploratory_analysis.ipynb
├── powerbi/                  # （Power BI 复现参考）
├── assets/
│   ├── dashboard/            # 4页HTML仪表盘 + 图表截图
│   └── eda/                  # 探索性图表
└── docs/
    ├── analysis_framework.md
    ├── analysis_report.md
    ├── audit_report.md
    ├── data_dictionary.md
    ├── metric_definition.md
    ├── debug_log.md
    ├── powerbi_setup.md
    └── interview_guide.md
```