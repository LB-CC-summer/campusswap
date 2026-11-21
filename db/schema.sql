-- =============================================================
-- 校易集 CampusSwap · 数据库结构 v2.0
-- 目标库：MySQL 8.0.16+（用到 CHECK 约束、JSON、生成列）
-- 规模：16 张表（概念实体 14 个，聊天授权与审计日志为支撑实体）
-- 配套：seed.sql（种子数据）、docs/uml/10-er.puml（E-R 图）
-- 约定：
--   1. 引擎 InnoDB，字符集 utf8mb4（昵称/描述含 emoji）
--   2. 时间统一 DATETIME(3)，毫秒精度，避免并发排序歧义
--   3. 金额 DECIMAL(10,2)，禁止 FLOAT
--   4. 主键 BIGINT UNSIGNED 自增；业务唯一性靠唯一索引，不靠应用层判断
--   5. 删除策略：业务数据一律软删除/状态位，不用物理 DELETE（交易凭证要留）
--   6. 两处"部分唯一"用生成列实现：trade.confirmed_product_id、
--      chat_access_grant.active_report_id（MySQL 8 无部分唯一索引）
-- =============================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- -------------------------------------------------------------
-- 1. 校区（独立成表，后台可增删，前端筛选项自动出现）
-- -------------------------------------------------------------
CREATE TABLE campus (
  id            BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  name          VARCHAR(32)  NOT NULL COMMENT '全称“大学城校区”，用于详情页/个人中心',
  short_name    VARCHAR(20)  NOT NULL COMMENT '简称“大学城”，用于首页筛选器/标签，前端按场景选字段，不做截取',
  city          VARCHAR(32)  NOT NULL COMMENT '广州/揭阳',
  is_cross_city TINYINT(1)   NOT NULL DEFAULT 0 COMMENT '1=跨市，只能邮寄',
  sort_no       INT          NOT NULL DEFAULT 0,
  is_enabled    TINYINT(1)   NOT NULL DEFAULT 1 COMMENT '停用后不出现在发布表单与筛选器',
  created_at    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY uk_campus_name (name),
  UNIQUE KEY uk_campus_short_name (short_name),
  KEY idx_enabled_sort (is_enabled, sort_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='校区';

-- -------------------------------------------------------------
-- 2. 用户（只存登录凭证与角色，敏感资料拆到 user_profile）
-- -------------------------------------------------------------
CREATE TABLE user (
  id            BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  email         VARCHAR(64)  NOT NULL COMMENT '学号邮箱，用于校内认证，不对外展示',
  password_hash VARCHAR(100) NOT NULL COMMENT 'BCrypt，禁止明文/MD5',
  nickname      VARCHAR(32)  NOT NULL,
  avatar_url    VARCHAR(255) NULL,
  role          ENUM('user','admin','super_admin') NOT NULL DEFAULT 'user',
  status        ENUM('active','disabled') NOT NULL DEFAULT 'active',
  disabled_reason VARCHAR(200) NULL,
  created_at    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  last_login_at DATETIME(3)  NULL,
  UNIQUE KEY uk_user_email (email),
  KEY idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户';

CREATE TABLE user_profile (
  user_id         BIGINT UNSIGNED PRIMARY KEY,
  campus_id       BIGINT UNSIGNED NOT NULL,
  verified_status ENUM('none','verified') NOT NULL DEFAULT 'none' COMMENT '只显示“已认证”徽章',
  phone_enc       VARBINARY(255) NULL COMMENT 'AES 加密存储，解密仅在后端',
  allow_contact   TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否允许他人发起联系方式交换',
  updated_at      DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  KEY idx_campus (campus_id),
  CONSTRAINT fk_profile_user   FOREIGN KEY (user_id)   REFERENCES user(id)   ON DELETE CASCADE,
  CONSTRAINT fk_profile_campus FOREIGN KEY (campus_id) REFERENCES campus(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户资料（1:1）';

-- -------------------------------------------------------------
-- 3. 分类（类目属性用 JSON，不为每个类目建表）
-- -------------------------------------------------------------
CREATE TABLE category (
  id        BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  name      VARCHAR(32) NOT NULL,
  parent_id BIGINT UNSIGNED NULL,
  sort_no   INT NOT NULL DEFAULT 0,
  KEY idx_parent (parent_id),
  CONSTRAINT fk_category_parent FOREIGN KEY (parent_id) REFERENCES category(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品分类';

-- -------------------------------------------------------------
-- 4. 商品
-- -------------------------------------------------------------
CREATE TABLE product (
  id            BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  seller_id     BIGINT UNSIGNED NOT NULL,
  category_id   BIGINT UNSIGNED NOT NULL,
  campus_id     BIGINT UNSIGNED NOT NULL,
  title         VARCHAR(80)   NOT NULL,
  description   TEXT          NULL,
  price         DECIMAL(10,2) NOT NULL,
  support_mail  TINYINT(1)    NOT NULL DEFAULT 0 COMMENT '揭阳跨市场景的唯一履约路径',
  status        ENUM('draft','on_sale','reserved','sold','removed') NOT NULL DEFAULT 'draft'
                COMMENT 'draft 草稿 / on_sale 在售 / reserved 已预订 / sold 已售出 / removed 已下架',
  attributes    JSON          NULL COMMENT '类目差异属性，如 {"book_name":"高等数学"}',
  view_count    INT UNSIGNED  NOT NULL DEFAULT 0,
  published_at  DATETIME(3)   NULL,
  created_at    DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at    DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  KEY idx_market (status, campus_id, category_id, published_at)
    COMMENT '集市列表按 status IN (on_sale, reserved) 过滤，再按校区/分类/时间排序',
  KEY idx_seller (seller_id, status),
  KEY idx_mail   (support_mail),
  CONSTRAINT ck_price_nonneg CHECK (price >= 0),
  CONSTRAINT fk_product_seller   FOREIGN KEY (seller_id)   REFERENCES user(id)   ON DELETE RESTRICT,
  CONSTRAINT fk_product_category FOREIGN KEY (category_id) REFERENCES category(id) ON DELETE RESTRICT,
  CONSTRAINT fk_product_campus   FOREIGN KEY (campus_id)   REFERENCES campus(id)   ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品';

CREATE TABLE product_image (
  id         BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  product_id BIGINT UNSIGNED NOT NULL,
  url        VARCHAR(255) NOT NULL,
  sort_no    INT NOT NULL DEFAULT 0,
  KEY idx_product (product_id, sort_no),
  CONSTRAINT fk_image_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品图片（1:N）';

-- -------------------------------------------------------------
-- 5. 收藏（多对多，唯一索引防重复收藏）
-- -------------------------------------------------------------
CREATE TABLE favorite (
  id         BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY uk_user_product (user_id, product_id),
  KEY idx_product (product_id),
  CONSTRAINT fk_fav_user    FOREIGN KEY (user_id)    REFERENCES user(id)    ON DELETE CASCADE,
  CONSTRAINT fk_fav_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='收藏';

-- -------------------------------------------------------------
-- 6. 会话与消息
-- -------------------------------------------------------------
CREATE TABLE conversation (
  id             BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  product_id     BIGINT UNSIGNED NOT NULL,
  buyer_id       BIGINT UNSIGNED NOT NULL,
  seller_id      BIGINT UNSIGNED NOT NULL,
  last_message_at DATETIME(3) NULL,
  buyer_unread   INT UNSIGNED NOT NULL DEFAULT 0,
  seller_unread  INT UNSIGNED NOT NULL DEFAULT 0,
  created_at     DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY uk_product_pair (product_id, buyer_id, seller_id) COMMENT '同一商品同一买卖方只有一条会话',
  KEY idx_buyer  (buyer_id, last_message_at),
  KEY idx_seller (seller_id, last_message_at),
  CONSTRAINT ck_conv_not_self CHECK (buyer_id <> seller_id),
  CONSTRAINT fk_conv_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE,
  CONSTRAINT fk_conv_buyer   FOREIGN KEY (buyer_id)   REFERENCES user(id)    ON DELETE RESTRICT,
  CONSTRAINT fk_conv_seller  FOREIGN KEY (seller_id)  REFERENCES user(id)    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='会话（商品ID+买家+卖家）';

CREATE TABLE message (
  id              BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  conversation_id BIGINT UNSIGNED NOT NULL,
  sender_id       BIGINT UNSIGNED NOT NULL,
  type            ENUM('text','image','product_card','system') NOT NULL DEFAULT 'text',
  content         TEXT NULL COMMENT '打码后的文本，原文不落库',
  created_at      DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  KEY idx_conv_time (conversation_id, id),
  CONSTRAINT fk_msg_conv   FOREIGN KEY (conversation_id) REFERENCES conversation(id) ON DELETE CASCADE,
  CONSTRAINT fk_msg_sender FOREIGN KEY (sender_id)       REFERENCES user(id)         ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='消息';

-- -------------------------------------------------------------
-- 7. 联系方式交换、拉黑
-- -------------------------------------------------------------
CREATE TABLE contact_exchange (
  id              BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  conversation_id BIGINT UNSIGNED NOT NULL,
  requester_id    BIGINT UNSIGNED NOT NULL,
  target_id       BIGINT UNSIGNED NOT NULL,
  status          ENUM('pending','accepted','closed') NOT NULL DEFAULT 'pending',
  created_at      DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  accepted_at     DATETIME(3) NULL,
  closed_at       DATETIME(3) NULL,
  KEY idx_conv (conversation_id),
  CONSTRAINT ck_exchange_not_self CHECK (requester_id <> target_id),
  CONSTRAINT fk_exchange_conv FOREIGN KEY (conversation_id) REFERENCES conversation(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='联系方式交换申请';

CREATE TABLE block (
  id         BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  blocker_id BIGINT UNSIGNED NOT NULL,
  blocked_id BIGINT UNSIGNED NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY uk_block_pair (blocker_id, blocked_id),
  KEY idx_blocked (blocked_id),
  CONSTRAINT ck_block_not_self CHECK (blocker_id <> blocked_id),
  CONSTRAINT fk_block_user FOREIGN KEY (blocker_id) REFERENCES user(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='拉黑';

-- -------------------------------------------------------------
-- 8. 交易（重点：并发只允许一单）
-- -------------------------------------------------------------
CREATE TABLE trade (
  id            BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  product_id    BIGINT UNSIGNED NOT NULL,
  buyer_id      BIGINT UNSIGNED NOT NULL,
  seller_id     BIGINT UNSIGNED NOT NULL,
  status        ENUM('pending','confirmed','completed','cancelled','rejected','aborted')
                NOT NULL DEFAULT 'confirmed'
                COMMENT '先到先得：买家点「立即购买」即写入 confirmed；pending/rejected 为兼容保留，不再产生',
  delivery      ENUM('meetup','mail') NOT NULL DEFAULT 'meetup',
  cancel_reason VARCHAR(200) NULL,
  created_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  confirmed_at  DATETIME(3) NULL,
  completed_at  DATETIME(3) NULL,
  -- 只有“已确认”的交易占用商品位；取消/完成/中止后自动置空，商品可再次成交
  -- 先到先得：INSERT 时即由唯一索引判定，第二个买家直接拿 1062
  confirmed_product_id BIGINT UNSIGNED
    GENERATED ALWAYS AS (IF(status = 'confirmed', product_id, NULL)) STORED,
  UNIQUE KEY uk_confirmed_product (confirmed_product_id),
  KEY idx_buyer  (buyer_id, status),
  KEY idx_seller (seller_id, status),
  CONSTRAINT ck_trade_not_self CHECK (buyer_id <> seller_id),
  CONSTRAINT fk_trade_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE RESTRICT,
  CONSTRAINT fk_trade_buyer   FOREIGN KEY (buyer_id)   REFERENCES user(id)    ON DELETE RESTRICT,
  CONSTRAINT fk_trade_seller  FOREIGN KEY (seller_id)  REFERENCES user(id)    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='交易单';

-- -------------------------------------------------------------
-- 9. 举报 + 按次授权查看聊天片段 + 审计日志
-- -------------------------------------------------------------
CREATE TABLE report (
  id                BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  reporter_id       BIGINT UNSIGNED NOT NULL,
  target_type       ENUM('product','user','conversation') NOT NULL,
  target_id         BIGINT UNSIGNED NOT NULL COMMENT '按 target_type 解释为商品/用户/会话ID',
  conversation_id   BIGINT UNSIGNED NULL COMMENT '会话类举报必填，用于限定授权范围',
  type              ENUM('fake_info','prohibited','harassment','fraud','contact_leak','other') NOT NULL,
  reason            VARCHAR(500) NOT NULL,
  evidence_urls     JSON NULL COMMENT '举报人上传的截图',
  allow_chat_access TINYINT(1) NOT NULL DEFAULT 0 COMMENT '举报人是否同意平台查看相关聊天片段',
  status            ENUM('pending','processing','resolved','rejected') NOT NULL DEFAULT 'pending',
  handler_id        BIGINT UNSIGNED NULL,
  result            ENUM('none','warning','content_removed','product_removed','account_disabled') NOT NULL DEFAULT 'none',
  handle_note       VARCHAR(500) NULL,
  created_at        DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  handled_at        DATETIME(3) NULL,
  KEY idx_status_time (status, created_at),
  KEY idx_target (target_type, target_id),
  KEY idx_reporter (reporter_id),
  CONSTRAINT fk_report_reporter FOREIGN KEY (reporter_id) REFERENCES user(id) ON DELETE RESTRICT,
  CONSTRAINT fk_report_handler  FOREIGN KEY (handler_id)  REFERENCES user(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='举报';

CREATE TABLE chat_access_grant (
  id              BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  report_id       BIGINT UNSIGNED NOT NULL,
  admin_id        BIGINT UNSIGNED NOT NULL,
  conversation_id BIGINT UNSIGNED NOT NULL,
  window_start    DATETIME(3) NOT NULL COMMENT '默认举报前 7 天',
  window_end      DATETIME(3) NOT NULL,
  reason          VARCHAR(200) NOT NULL COMMENT '管理员填写的查看理由',
  status          ENUM('active','expired','revoked') NOT NULL DEFAULT 'active',
  created_at      DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  expires_at      DATETIME(3) NOT NULL COMMENT '创建后 24 小时',
  -- 只对 status='active' 生效的"部分唯一"：同一举报单 + 同一管理员
  -- 同时最多一条有效授权；过期/撤销后自动让位，可以再次申请
  active_report_id BIGINT UNSIGNED
    GENERATED ALWAYS AS (IF(status = 'active', report_id, NULL)) STORED,
  UNIQUE KEY uk_active_grant (active_report_id, admin_id),
  KEY idx_report (report_id),
  CONSTRAINT fk_grant_report FOREIGN KEY (report_id) REFERENCES report(id) ON DELETE CASCADE,
  CONSTRAINT fk_grant_admin  FOREIGN KEY (admin_id)  REFERENCES user(id)  ON DELETE RESTRICT,
  CONSTRAINT ck_grant_window CHECK (window_start < window_end)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='聊天片段查看授权（按次、限时、限范围）';

CREATE TABLE admin_audit_log (
  id          BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  admin_id    BIGINT UNSIGNED NOT NULL,
  action      VARCHAR(40) NOT NULL COMMENT 'grant_view / disable_user / remove_product / handle_report ...',
  target_type VARCHAR(20) NOT NULL,
  target_id   BIGINT UNSIGNED NOT NULL,
  detail      JSON NULL COMMENT '查看了哪些 message_id、IP、UA 等',
  created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  KEY idx_admin_time (admin_id, created_at),
  KEY idx_target (target_type, target_id),
  CONSTRAINT fk_audit_admin FOREIGN KEY (admin_id) REFERENCES user(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='后台操作审计（不可删改）';

-- -------------------------------------------------------------
-- 10. 智能体会话（只存会话与上下文摘要，消息由业务服务落库）
-- -------------------------------------------------------------
CREATE TABLE agent_session (
  id         BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL,
  context    JSON NULL COMMENT '已确认条件：预算/校区/分类等，用于多轮继承',
  status     ENUM('active','closed') NOT NULL DEFAULT 'active',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  KEY idx_user (user_id, status),
  CONSTRAINT fk_agent_user FOREIGN KEY (user_id) REFERENCES user(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='智能体会话上下文';

SET FOREIGN_KEY_CHECKS = 1;
