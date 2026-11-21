-- =============================================================
-- 校易集 CampusSwap · 种子数据 v1.0
-- 执行顺序：先 schema.sql，再本文件
-- 说明：
--   1. 校区数据来自需求文档的五个校区，不得改动名称（AC-17/AC-18 依赖）
--   2. 密码列是占位值，首次部署后用后端脚本重置为真实 BCrypt：
--        UPDATE user SET password_hash = '<bcrypt>' WHERE email = 'admin@gdut.edu.cn';
--      占位值不可用于登录，避免把弱口令带进仓库
--   3. 商品为演示数据，仅用于验收 AC-01/AC-02 的列表与筛选
-- =============================================================

SET NAMES utf8mb4;

-- -------------------------------------------------------------
-- 1. 校区（五校区，广州四校区同城面交，揭阳跨市需邮寄）
-- -------------------------------------------------------------
INSERT INTO campus (id, name, short_name, city, is_cross_city, sort_no, is_enabled) VALUES
  (1, '大学城校区', '大学城', '广州', 0, 10, 1),
  (2, '东风路校区', '东风路', '广州', 0, 20, 1),
  (3, '龙洞校区',   '龙洞',   '广州', 0, 30, 1),
  (4, '番禺校区',   '番禺',   '广州', 0, 40, 1),
  (5, '揭阳校区',   '揭阳',   '揭阳', 1, 50, 1);

-- -------------------------------------------------------------
-- 2. 分类（与原型首页的四个入口一致，另留「其他」兜底）
-- -------------------------------------------------------------
INSERT INTO category (id, name, parent_id, sort_no) VALUES
  (1, '数码', NULL, 10),
  (2, '教材', NULL, 20),
  (3, '生活', NULL, 30),
  (4, '运动', NULL, 40),
  (5, '其他', NULL, 50),
  (6, '电脑外设', 1, 11),
  (7, '手机平板', 1, 12),
  (8, '专业课教材', 2, 21),
  (9, '公共课教材', 2, 22);

-- -------------------------------------------------------------
-- 3. 账号（1 超管 + 5 普通用户，覆盖五个校区；密码均为占位，需重置）
-- -------------------------------------------------------------
INSERT INTO user (id, email, password_hash, nickname, role, status, created_at) VALUES
  (1, 'admin@gdut.edu.cn',   '$2b$12$PLACEHOLDER_REPLACE_ME_000000000000000000000000000000', '平台管理员', 'super_admin', 'active', NOW(3)),
  (2, '3124004428@gdut.edu.cn', '$2b$12$PLACEHOLDER_REPLACE_ME_000000000000000000000000000000', '阿赖', 'user', 'active', NOW(3)),
  (3, '3124004429@gdut.edu.cn', '$2b$12$PLACEHOLDER_REPLACE_ME_000000000000000000000000000000', '小廖', 'user', 'active', NOW(3)),
  (4, '3224004305@gdut.edu.cn', '$2b$12$PLACEHOLDER_REPLACE_ME_000000000000000000000000000000', '小柯', 'user', 'active', NOW(3)),
  (5, '3224004345@gdut.edu.cn', '$2b$12$PLACEHOLDER_REPLACE_ME_000000000000000000000000000000', '小翁', 'user', 'active', NOW(3)),
  (6, '3224004304@gdut.edu.cn', '$2b$12$PLACEHOLDER_REPLACE_ME_000000000000000000000000000000', '小胡', 'user', 'active', NOW(3));

INSERT INTO user_profile (user_id, campus_id, verified_status, allow_contact) VALUES
  (1, 1, 'verified', 1),   -- 管理员
  (2, 1, 'verified', 1),   -- 大学城，卖家
  (3, 1, 'verified', 1),   -- 大学城，买家
  (4, 5, 'none', 1),       -- 揭阳，卖家（跨市，商品须支持邮寄）
  (5, 3, 'none', 1),       -- 龙洞，卖家
  (6, 2, 'none', 1);       -- 东风路，卖家

-- -------------------------------------------------------------
-- 4. 演示商品（覆盖：不同校区、是否支持邮寄、有无图片）
-- -------------------------------------------------------------
INSERT INTO product (id, seller_id, category_id, campus_id, title, description, price, support_mail, status, attributes, view_count, published_at, created_at) VALUES
  (1001, 2, 6, 1, 'AOC 24 英寸显示器',
   '自用一年，无坏点，带 HDMI 线，宿舍写代码够用。', 260.00, 0, 'on_sale',
   '{"interface":"HDMI","size_inch":24,"condition":"九成新"}', 37,
   NOW(3) - INTERVAL 2 DAY, NOW(3) - INTERVAL 2 DAY),
  (1002, 2, 8, 1, '高等数学教材·第七版',
   '上下册，有少量笔记，不影响阅读。', 28.00, 0, 'on_sale',
   '{"book_name":"高等数学","edition":"第七版","has_notes":true}', 52,
   NOW(3) - INTERVAL 5 DAY, NOW(3) - INTERVAL 5 DAY),
  (1003, 4, 9, 5, '大学英语四级真题（含听力音频）',
   '揭阳校区，可邮寄，邮费到付。', 15.00, 1, 'on_sale',
   '{"book_name":"四级真题","edition":"2025版","has_notes":false}', 12,
   NOW(3) - INTERVAL 1 DAY, NOW(3) - INTERVAL 1 DAY),
  (1004, 5, 3, 3, '宿舍台灯（可调光）',
   '三档调光，龙洞校区自取。', 25.00, 0, 'on_sale',
   '{"power":"USB 供电","condition":"八成新"}', 8,
   NOW(3) - INTERVAL 6 HOUR, NOW(3) - INTERVAL 6 HOUR),
  (1005, 6, 4, 2, '羽毛球拍（双拍装）',
   '东风路校区，拍线完好，送两个球。', 45.00, 0, 'on_sale',
   '{"type":"双拍","condition":"九成新"}', 19,
   NOW(3) - INTERVAL 3 DAY, NOW(3) - INTERVAL 3 DAY);

INSERT INTO product_image (product_id, url, sort_no) VALUES
  (1001, '/static/demo/1001-a.jpg', 1),
  (1001, '/static/demo/1001-b.jpg', 2),
  (1002, '/static/demo/1002-a.jpg', 1),
  (1003, '/static/demo/1003-a.jpg', 1);

-- -------------------------------------------------------------
-- 5. 演示会话（买家 3 与商品 1001 同在大学城；消息内容为打码后文本）
-- -------------------------------------------------------------
INSERT INTO conversation (id, product_id, buyer_id, seller_id, last_message_at, buyer_unread, seller_unread, created_at) VALUES
  (5001, 1001, 3, 2, NOW(3) - INTERVAL 2 HOUR, 1, 0, NOW(3) - INTERVAL 3 HOUR);

INSERT INTO message (conversation_id, sender_id, type, content, created_at) VALUES
  (5001, 3, 'text', '你好，显示器还在吗？接口是 HDMI 吗？', NOW(3) - INTERVAL 3 HOUR),
  (5001, 2, 'text', '在的，HDMI 和 DP 都有。', NOW(3) - INTERVAL 2 HOUR);

-- -------------------------------------------------------------
-- 6. 演示交易（同校区面交，一笔 confirmed；用于验证 uk_confirmed_product 与 AC-10）
-- -------------------------------------------------------------
INSERT INTO trade (id, product_id, buyer_id, seller_id, status, delivery, created_at, confirmed_at) VALUES
  (7001, 1002, 3, 2, 'confirmed', 'meetup', NOW(3) - INTERVAL 4 HOUR, NOW(3) - INTERVAL 4 HOUR);

UPDATE product SET status = 'reserved' WHERE id = 1002;
