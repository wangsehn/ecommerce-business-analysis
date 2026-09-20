# -*- coding: utf-8 -*-
"""
MySQL 建库建表 + 数据导入引擎
================================
用法：
    python src/load_mysql.py          # 读取环境变量 MYSQL_PWD 或使用 --password
    # 例如：
    #   $env:MYSQL_PWD='123456'; python src/load_mysql.py

功能：
    1. 连接 MySQL（支持外网 mysql 命令不存在，故用 pymysql 直连）。
    2. 建库 ecommerce_bas（UTF-8）。
    3. 建 8 张表（含主键、外键、索引，引擎 InnoDB）。
    4. 逐表批量导入 data/cleaned/*.csv。

说明：
    - 密码通过环境变量 MYSQL_PWD 传入，避免把凭据写死在脚本里（比原项目硬编码更安全）。
    - 建表 SQL 保留 primary key 与外键约束，保证多表关系在数据库层面可见。
"""
import os
import pandas as pd
import pymysql
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLN = os.path.join(BASE, "data", "cleaned")

DB_USER = os.getenv("MYSQL_USER", "root")
DB_PASS = os.getenv("MYSQL_PWD", "")
DB_HOST = os.getenv("MYSQL_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("MYSQL_PORT", "3306"))
DB_NAME = os.getenv("MYSQL_DB", "ecommerce_bas")

DDL = """
CREATE DATABASE IF NOT EXISTS {db} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE {db};

CREATE TABLE IF NOT EXISTS category_name (
    product_category_name VARCHAR(128) PRIMARY KEY,
    product_category_name_english VARCHAR(128) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sellers (
    seller_id VARCHAR(64) PRIMARY KEY,
    seller_zip_code_prefix INT NULL,
    seller_city  VARCHAR(128) NULL,
    seller_state VARCHAR(4) NULL,
    KEY idx_sset (seller_state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS products (
    product_id VARCHAR(64) PRIMARY KEY,
    product_category_name VARCHAR(128) NULL,
    product_name_lenght      FLOAT NULL,
    product_description_lenght FLOAT NULL,
    product_photos_qty       FLOAT NULL,
    product_weight_g         FLOAT NULL,
    product_length_cm        FLOAT NULL,
    product_height_cm        FLOAT NULL,
    product_width_cm         FLOAT NULL,
    KEY idx_pcat (product_category_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS customers (
    customer_id          VARCHAR(64) PRIMARY KEY,
    customer_unique_id   VARCHAR(64) NOT NULL,
    customer_zip_code_prefix INT NULL,
    customer_city        VARCHAR(128) NULL,
    customer_state       VARCHAR(4) NULL,
    KEY idx_unique (customer_unique_id),
    KEY idx_state  (customer_state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS orders (
    order_id                   VARCHAR(64) PRIMARY KEY,
    customer_id                VARCHAR(64) NOT NULL,
    order_status               VARCHAR(32) NULL,
    order_purchase_timestamp   DATETIME NULL,
    order_approved_at          DATETIME NULL,
    order_delivered_carrier_date DATETIME NULL,
    order_delivered_customer_date DATETIME NULL,
    order_estimated_delivery_date DATETIME NULL,
    KEY idx_orders_cust (customer_id),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS order_items (
    order_id           VARCHAR(64) NOT NULL,
    order_item_id      INT NOT NULL,
    product_id         VARCHAR(64) NULL,
    seller_id          VARCHAR(64) NULL,
    shipping_limit_date DATETIME NULL,
    price              DECIMAL(12,2) NULL,
    freight_value      DECIMAL(12,2) NULL,
    PRIMARY KEY (order_id, order_item_id),
    KEY idx_product (product_id),
    KEY idx_seller (seller_id),
    CONSTRAINT fk_items_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT fk_items_product FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT fk_items_seller FOREIGN KEY (seller_id) REFERENCES sellers(seller_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS order_payments (
    order_id             VARCHAR(64) NOT NULL,
    payment_sequential   INT NOT NULL,
    payment_type         VARCHAR(32) NULL,
    payment_installments INT NULL,
    payment_value        DECIMAL(12,2) NULL,
    PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT fk_pay_order FOREIGN KEY (order_id) REFERENCES orders(order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS order_reviews (
    review_id                VARCHAR(64) PRIMARY KEY,
    order_id                 VARCHAR(64) NOT NULL,
    review_score             INT NULL,
    review_comment_title     TEXT NULL,
    review_comment_message   TEXT NULL,
    review_creation_date     DATETIME NULL,
    review_answer_timestamp  DATETIME NULL,
    KEY idx_review_order (order_id),
    CONSTRAINT fk_review_order FOREIGN KEY (order_id) REFERENCES orders(order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
"""

TABLES = [
    "category_name", "sellers", "products", "customers", "orders",
    "order_items", "order_payments", "order_reviews",
]


def connect_root():
    return pymysql.connect(host=DB_HOST, port=DB_PORT, user=DB_USER, password=DB_PASS)


def ensure_db():
    conn = connect_root()
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"CREATE DATABASE IF NOT EXISTS {DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
            )
        conn.commit()
        print(f"[DB] {DB_NAME} 就绪")
    finally:
        conn.close()


def init_schema(engine: Engine):
    # DDL 中 CREATE DATABASE/USE 由 root 连接完成；此处仅通过已命中的库执行建表
    with engine.connect() as con:
        for stmt in [s for s in DDL.split(";") if s.strip() and "CREATE DATABASE" not in s and "USE " not in s]:
            stmt = stmt.strip()
            if not stmt:
                continue
            con.execute(text(stmt))
        con.commit()
    print("[SCHEMA] 建表完成")


def load_csv_to_mysql(engine: Engine):
    for name in TABLES:
        path = os.path.join(CLN, f"{name}.csv")
        if not os.path.exists(path):
            print(f"[SKIP] 缺少 {path}")
            continue
        df = pd.read_csv(path)
        df.to_sql(name, con=engine, if_exists="append", index=False, method="multi", chunksize=5000)
        print(f"[LOAD] {name}: {len(df)} 行")


def main():
    ensure_db()
    engine = create_engine(f"mysql+pymysql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}?charset=utf8mb4")
    init_schema(engine)
    load_csv_to_mysql(engine)
    with engine.connect() as con:
        rows = con.execute(text(
            "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema=:d",
        ), {"d": DB_NAME}).fetchall()
        for r in rows:
            print(f"[COUNT] {r[0]}: {r[1]}")
    print("全部导入完成。")


if __name__ == "__main__":
    main()