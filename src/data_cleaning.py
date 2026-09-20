# -*- coding: utf-8 -*-
"""
数据清洗模块
============
面向受众：数据分析作品集读者 / 面试官。

本脚本将 data/raw/ 下的 8 个 Olist 原始 CSV 清洗为 data/cleaned/ 下可直接入库 MySQL 的 CSV。

清洗原则（关键口径，见 docs/data_dictionary.md）：
1. 统一时间字段为 pandas datetime 并补齐简单缺失（orders 各时间节点缺失保留，代表订单未走到该环节）。
2. 类型转换：数值字段转 float/int，邮编等转整型。
3. 重复处理：
   - order_reviews 按 review_id 去重（实测 99224 -> 98410 行，去 814 行重复评价）。
   - 其余表按其主键检查唯一性（orders/order_items 等实测无重复行）。
4. 商品表：product_category_name 缺失填 'unknown'；基础维度列缺失按原项目思路处理，
   但对重量/尺寸仍保留原生缺失(空串)以便数据质量报告展示，入库时再按策略处理。
5. 不删除任何订单行（保留 cancelled/unavailable 等状态用于数据质量与口径对比），
   有效订单口径在 SQL 侧用 order_status='delivered' 控制。
6. 品类名保留葡语原名 + 英文翻译，中文展示交给 Power BI/分析脚本做映射。

输出文件：
    data/cleaned/{customers,orders,order_items,order_payments,order_reviews,products,sellers,category_name}.csv
"""
import os
import pandas as pd

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(BASE, "data", "raw")
CLN = os.path.join(BASE, "data", "cleaned")
os.makedirs(CLN, exist_ok=True)

TIME_COLS = {
    "orders": ["order_purchase_timestamp", "order_approved_at",
               "order_delivered_carrier_date", "order_delivered_customer_date",
               "order_estimated_delivery_date"],
    "order_items": ["shipping_limit_date"],
    "order_reviews": ["review_creation_date", "review_answer_timestamp"],
}


def _load(name):
    return pd.read_csv(os.path.join(RAW, f"olist_{name}_dataset.csv"))


def clean_customers():
    df = _load("customers")
    df["customer_zip_code_prefix"] = df["customer_zip_code_prefix"].astype(int)
    return df


def clean_orders():
    df = _load("orders")
    for c in TIME_COLS["orders"]:
        df[c] = pd.to_datetime(df[c], errors="coerce")
    df["customer_id"] = df["customer_id"].astype(str)
    return df


def clean_order_items():
    df = _load("order_items")
    for c in TIME_COLS["order_items"]:
        df[c] = pd.to_datetime(df[c], errors="coerce")
    df["price"] = df["price"].astype(float)
    df["freight_value"] = df["freight_value"].astype(float)
    return df


def clean_order_payments():
    df = _load("order_payments")
    df["payment_value"] = df["payment_value"].astype(float)
    df["payment_installments"] = df["payment_installments"].astype(int)
    return df


def clean_order_reviews():
    df = _load("order_reviews")
    for c in TIME_COLS["order_reviews"]:
        df[c] = pd.to_datetime(df[c], errors="coerce")
    # 去重重复评价（同 review_id 保留第一条）
    before = len(df)
    df = df.drop_duplicates(subset=["review_id"], keep="first").copy()
    print(f"[reviews] {before} -> {len(df)} (去重 {before - len(df)})")
    return df


def clean_products():
    df = _load("products")
    df["product_category_name"] = df["product_category_name"].fillna("unknown")
    return df


def clean_sellers():
    df = _load("sellers")
    return df


def clean_category():
    return pd.read_csv(os.path.join(RAW, "product_category_name_translation.csv"))


def main():
    jobs = {
        "customers": clean_customers,
        "orders": clean_orders,
        "order_items": clean_order_items,
        "order_payments": clean_order_payments,
        "order_reviews": clean_order_reviews,
        "products": clean_products,
        "sellers": clean_sellers,
        "category_name": clean_category,
    }
    for name, fn in jobs.items():
        df = fn()
        out = os.path.join(CLN, f"{name}.csv")
        df.to_csv(out, index=False)
        print(f"[OK] {name}  shape={df.shape}  ->  {out}")
    print("全部清洗完成。")


if __name__ == "__main__":
    main()