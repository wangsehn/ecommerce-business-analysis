# data/ 目录说明

## raw/（原始数据，本仓库不提交，请自行下载）
使用官方 [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)。

下载 `olist_customers_dataset.csv, olist_orders_dataset.csv, olist_order_items_dataset.csv, olist_order_payments_dataset.csv, olist_order_reviews_dataset.csv, olist_products_dataset.csv, olist_sellers_dataset.csv, product_category_name_translation.csv` 放至此目录。

> 提示：Kaggle 需登录。可选用已镜像这些原始文件名的公开 GitHub 仓库 raw 直链下载（例如
> `https://raw.githubusercontent.com/<repo>/.../olist_orders_dataset.csv`），下载后请与官方校验。

## cleaned/（清洗后数据，由 src/data_cleaning.py 生成）
清洗规则见 `src/data_cleaning.py` 与 `docs/data_dictionary.md`：
- 统一时间字段、类型转换
- order_reviews 按 review_id 去重（99224 → 98410）
- 不删除订单（非交付单在 SQL 侧用 order_status='delivered' 过滤）

## 数据血缘
```
raw ──(src/data_cleaning.py)──> cleaned ──(src/load_mysql.py)──> MySQL(ecommerce_bas) ──SQL分析──> 结论
```