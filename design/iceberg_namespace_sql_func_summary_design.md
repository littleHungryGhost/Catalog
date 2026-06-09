# Iceberg Namespace SQL Function Summary Design

## 1. is_namespace_existed

SQL定义:
  CREATE OR REPLACE FUNCTION is_namespace_existed(
      p_namespace TEXT
  ) RETURNS JSONB
  LANGUAGE plpgsql STABLE STRICT SET search_path = ''

主要流程:
  1. 参数校验，p_namespace 为 NULL 或空串则返回P0001错误码
  2. 调元数据接口查元信息表，检查 namespace 是否存在
  3. 存在返回 {"exists": true}，不存在返回 {"exists": false}（不抛异常）

---

## 2. load_namespace

SQL定义:
  CREATE OR REPLACE FUNCTION load_namespace(
      p_namespace TEXT
  ) RETURNS JSONB
  LANGUAGE plpgsql STABLE STRICT SET search_path = ''

主要流程:
  1. 参数校验，p_namespace 为 NULL 或空串则返回P0001错误码
  2. 调元数据接口查元信息表，获取 namespace 信息和 properties
  3. 未找到则返回P0004错误码
  4. 构造并返回 {"namespace": [...], "properties": {...}} JSONB

---

## 3. list_namespaces

SQL定义:
  CREATE OR REPLACE FUNCTION list_namespaces(
      p_parent     TEXT    DEFAULT NULL,
      p_page_size  INTEGER DEFAULT 1000,
      p_page_token TEXT    DEFAULT NULL
  ) RETURNS JSONB
  LANGUAGE plpgsql STABLE STRICT SET search_path = ''

主要流程:
  1. 参数校验，p_page_size < 1 则返回P0001错误码
  2. 若 p_parent 非空，调元数据接口检查父级是否存在，不存在则返回P0004错误码
  3. 调元数据接口分页查询元信息表
  4. 返回 {"namespaces": [...], "next-page-token": "..."} JSONB

---

## 4. create_namespace

SQL定义:
  CREATE OR REPLACE FUNCTION create_namespace(
      p_namespace  TEXT,
      p_properties JSONB DEFAULT NULL
  ) RETURNS JSONB
  LANGUAGE plpgsql VOLATILE STRICT SET search_path = ''

主要流程:
  1. 参数校验，p_namespace 为 NULL 或空串则返回P0001错误码
  2. 元数据先写：调元数据接口写入元信息表
  3. SDK 后写：调 SDK 接口解析 S3 路径并创建 marker
  4. SDK 返回 location 后，调元数据接口更新 properties（补充 location 字段）
  5. 重新查元数据接口获取最终结果并返回

---

## 5. drop_namespace

SQL定义:
  CREATE OR REPLACE FUNCTION drop_namespace(
      p_namespace TEXT
  ) RETURNS JSONB
  LANGUAGE plpgsql VOLATILE STRICT SET search_path = ''

主要流程:
  1. 参数校验，p_namespace 为 NULL 或空串则返回P0001错误码
  2. 调元数据接口检查 namespace 是否存在，不存在则返回P0004错误码
  3. 调元数据接口检查 namespace 下是否有表，非空则返回P0005错误码
  4. 调元数据接口删除元信息表记录
  5. 调 SDK 接口清理
  6. 返回 {"success": true}

---

## 6. update_namespace_properties

SQL定义:
  CREATE OR REPLACE FUNCTION update_namespace_properties(
      p_namespace TEXT,
      p_removals  JSONB DEFAULT NULL,
      p_updates   JSONB DEFAULT NULL
  ) RETURNS JSONB
  LANGUAGE plpgsql VOLATILE STRICT SET search_path = ''

主要流程:
  1. 参数校验，p_namespace 为 NULL 或空串则返回P0001错误码；p_removals 和 p_updates 不能同时为空
  2. 校验 p_removals 格式（JSONB 数组）和 p_updates 格式（JSONB object）
  3. 检查 removals 和 updates 是否有交集，有交集则返回P0006错误码
  4. 调元数据接口更新元信息表
  5. 返回更新结果 JSONB：{"updated": [...], "removed": [...], "missing": [...]}

