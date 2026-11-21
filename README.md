# 校易集 CampusSwap

广东工业大学软件工程课程团队项目 · **拾集小队**

面向广工在校学生的校园二手交易平台，内嵌智能交易助手：买家说一句「我想买宿舍写代码用的显示器，300 以内，只要大学城校区」，就能拿到真实在售的商品清单、推荐理由与缺失信息提示；卖家拍张照片说一句话，就能拿到一份可以直接改的发布草稿。全程在平台内沟通，不公开手机号与微信。

**覆盖校区：** 大学城、东风路、龙洞、番禺、揭阳（沙河校区暂未列入，后台可随时扩展，新增校区不需发版）

---

## 第二次团队作业：原型设计 + 概要设计

### 交付物索引

| 交付物 | 位置 | 状态 |
|---|---|---|
| 系统设计说明书（SDD） | [Markdown](docs/01-系统设计说明书.md) ／ [PDF 37 页](docs/01-系统设计说明书.pdf) | 已交付 |
| 数据库设计说明书（DBDD） | [`docs/02-数据库设计说明书.md`](docs/02-数据库设计说明书.md) | 已交付（16 表 + `db/schema.sql`、`db/seed.sql`） |
| 核心接口设计说明书 | `docs/03-核心接口设计说明书.md` | 待提交（柯燕纯） |
| 智能体接口约定 | `docs/04-智能体接口约定.md` | 待提交（叶浚轩） |
| 原型走查记录 | [`docs/05-原型走查记录.md`](docs/05-原型走查记录.md) | 已交付（20 帧、四态 4/4） |
| UI 侧走查核对回复 | [`docs/06-走查问题核对与修复说明.md`](docs/06-走查问题核对与修复说明.md) | 已交付 |
| 提交前链接检查表 | [`docs/06-链接检查表.md`](docs/06-链接检查表.md) | 已交付 |
| UML 与架构图（12 张） | [`docs/uml/`](docs/uml/) | 11 张已交付，缺图 2-5（智能找物时序图） |
| 原型页面清单与截图 | [`docs/prototype/`](docs/prototype/) | 23 张截图已入库 |

> PDF 版本由上述 Markdown 排版导出，命名规范见 [`docs/README.md`](docs/README.md)。构建脚本见 [`tools/README.md`](tools/README.md)。

### 原型在线预览

| 端 | 链接 | 内容 |
|---|---|---|
| 前台（学生端） | [CampusS-11](https://www.figma.com/proto/pjrY4BLAguoyZz6eo7ufbN/CampusS-11) | F01–F11 + 4 个状态帧 + 聊天三变体 |
| 后台（管理端） | [CampusS-22](https://www.figma.com/proto/CelIX5lzPKjj01NfFALkxq/CampusS-22) | A00–A04 |

链接为 Presentation 模式，未登录即可查看。建议演示路径：集市首页 → 商品详情 → 智能找物 → 智能发布 → 交易中心 → 后台举报处理。逐页说明见 [`docs/prototype/README.md`](docs/prototype/README.md)。

### 本次设计的核心决策

设计说明书里论证的决策中，以下六条影响面最大，也是评审最可能追问的地方：

| 决策 | 结论 | 一句话理由 |
|---|---|---|
| 技术栈 | Python FastAPI + MySQL 8 + Vue 3 | 与智能体工具层同语言，避免前后端语言割裂 |
| 智能体形态 | 自建工具层 + 直连大模型 API，不用可视化编排平台 | 编排配置要能进版本库评审与回滚，答辩不依赖第三方平台可用性 |
| 交易模型 | 先到先得，下单即成交，不设卖家二次确认 | 并发正确性交给数据库生成列 + 唯一索引，一次 INSERT 定胜负 |
| 联系方式 | 聊天原文不落库，交换走独立表由用户主动填写并加密 | 「原文不落库」与「同意后可见」只有这样才能同时成立 |
| 智能体多轮 | 已确认条件存 `agent_session` 表，不用进程内字典 | 开发热重载与多进程会清空内存上下文 |
| 状态过滤 | 列表与检索返回在售 + 已预订，已预订置灰 | 商品被抢走后凭空消失，比看到「已被预订」更让人困惑 |

全部 10 项设计决策见设计说明书 2.6 节，设计变更与待执行项见其附录 A。

### 技术栈

| 层次 | 选型 |
|---|---|
| 前端 | Vue 3 + TypeScript + Vite + Element Plus |
| 后端 | Python 3.10 + FastAPI + SQLAlchemy 2.0 |
| 数据库 | MySQL 8.0（生成列 + 唯一索引承担交易并发唯一性） |
| 实时消息 | WebSocket |
| 智能体 | 自建工具层 + 外部大模型 API（不依赖第三方编排平台） |
| 部署 | 单台云服务器 + Nginx + Docker Compose |

---

## 第一次团队作业：团队展示 + 选题报告 + 需求分析

博客已发布于 <https://www.cnblogs.com/huahetai/p/23594599>。

全部稿件、答辩讲稿与演示文稿归档在 [`docs/blog/`](docs/blog/)，最终提交版为 [`07-博客终稿-精简计划版.md`](docs/blog/07-博客终稿-精简计划版.md)。保留多个历史版本是为了留存推演的修改轨迹，不是重复文件。

---

## 本地运行与部署

本章节面向想在自己机器上跑起来的人，以及负责部署的成员。部署图见 [`docs/uml/09-deployment.png`](docs/uml/09-deployment.png)。

### 环境要求

| 组件 | 版本 | 说明 |
|---|---|---|
| Python | 3.10+ | 后端运行环境 |
| MySQL | 8.0.16+ | 低于此版本不支持生成列上的函数索引 |
| Node.js | 18+ | 仅前端需要 |
| Docker + Docker Compose | 20.10+ / v2 | 生产部署方式 |
| Git | 2.30+ | — |

### 配置项

所有配置通过环境变量注入，**`.env` 文件不入版本库**。仓库提供 `.env.example` 作为模板，复制为 `.env` 后填写：

| 变量 | 必填 | 说明 |
|---|---|---|
| `APP_ENV` | 是 | `dev` / `prod` |
| `APP_PORT` | 否 | 默认 8080 |
| `DB_HOST` | 是 | 开发期为 `127.0.0.1`，容器内为 `mysql` |
| `DB_PORT` | 否 | 默认 3306 |
| `DB_NAME` | 是 | 数据库名 |
| `DB_USER` | 是 | 应用账号，只授予 DML 权限 |
| `DB_PASSWORD` | 是 | 数据库口令 |
| `JWT_SECRET` | 是 | 登录令牌签名密钥，随机 32 字节以上 |
| `PHONE_AES_KEY` | 是 | 手机号字段的 AES-GCM 密钥，32 字节 base64 |
| `LLM_API_BASE` | 是 | 大模型服务地址 |
| `LLM_API_KEY` | 是 | 大模型服务密钥 |
| `LLM_TIMEOUT` | 否 | 默认 5 秒，超时触发关键词降级 |
| `OSS_ENDPOINT` / `OSS_BUCKET` | 否 | 不填则图片落本地目录 |

生成密钥的参考命令：

```bash
python -c "import os,base64;print(base64.b64encode(os.urandom(32)).decode())"
```

### 开发环境启动

```bash
# 1. 安装依赖
pip install -r requirements.txt

# 2. 准备数据库
mysql -u root -p -e "CREATE DATABASE campusswap DEFAULT CHARSET utf8mb4;"

# 3. 建表与种子数据
python -m app.db.init_db
python -m app.db.seed          # 校区 5 条、分类、演示商品

# 4. 启动后端
uvicorn app.main:app --reload --port 8080

# 5. 前端（另开一个终端）
cd web && npm install && npm run dev
```

启动后：接口文档 <http://localhost:8080/docs>，前端 <http://localhost:5173>。

### 生产部署（Docker Compose）

```bash
# 1. 准备环境变量
cp .env.example .env
vim .env                       # 填入真实口令与密钥

# 2. 启动
docker compose up -d --build

# 3. 建表（首次）
docker compose exec app python -m app.db.init_db

# 4. 查看状态与日志
docker compose ps
docker compose logs -f app
```

Compose 编排三个容器：`nginx`（对外 443）、`app`（FastAPI，仅内网）、`mysql`（仅内网）。

### 部署约定

1. **仅 `nginx` 容器映射端口到宿主机**，`app` 与 `mysql` 不映射，避免绕过反向代理直连。
2. **`mysql` 不对公网开放**，数据库账号按最小权限分配：应用账号只有 DML 权限，建表由迁移脚本以管理员账号执行。
3. **`app` 容器不加 `--workers`**。会话上下文与限流计数若采用内存态，多 worker 会导致各进程状态不一致；本期已改用数据库表承载，但仍保持单进程以简化排查。
4. **密钥与口令只走环境变量**，`.env` 已在 `.gitignore` 中排除。
5. **开发与生产同一套 Compose 配置**，差异全部收敛到环境变量，避免"本地能跑、线上不能跑"。
6. **图片存储可切换**：开发期落本地卷，生产期配置 `OSS_*` 后自动切换，业务代码无需改动。

### 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 建表报 `1064` | MySQL 版本低于 8.0.16，不支持生成列函数索引 | 升级 MySQL |
| 接口返回 502 / 504 | 大模型超时 | 检查 `LLM_TIMEOUT`；系统会自动降级为关键词查询 |
| 静态资源 404 | nginx 未挂载前端产物目录 | 检查 compose 中的 volume 映射 |
| 中文乱码 | 数据库或连接未指定 utf8mb4 | 建库时指定 `DEFAULT CHARSET utf8mb4` |

---

## 仓库结构

```
campusswap/
├── README.md                    # 本文件
├── db/
│   ├── schema.sql               # 16 张表 DDL：生成列 + 唯一索引承担抢单并发
│   └── seed.sql                 # 五校区、分类与演示商品
├── docs/
│   ├── README.md                # 文档索引与排版规范
│   ├── 01-系统设计说明书.md / .pdf
│   ├── 02-数据库设计说明书.md
│   ├── 03-核心接口设计说明书.md   # 待提交
│   ├── 04-智能体接口约定.md       # 待提交
│   ├── 05-原型走查记录.md
│   ├── 06-走查问题核对与修复说明.md
│   ├── 06-链接检查表.md
│   ├── uml/                     # 12 张图的 .puml 与 .png（已入库 11 张）
│   ├── prototype/               # 原型链接、页面清单、screens/ 23 张截图
│   ├── blog/                    # 博客稿与答辩材料
│   └── pm/                      # 任务分派与协作记录
├── tools/                       # Markdown → DOCX → PDF 构建脚本
└── assets/                      # 答辩 PPT、图标资源
```

## 分支与协作

| 分支 | 用途 |
|---|---|
| `main` | 随时可演示的状态，只接受来自 `develop` 的合并 |
| `develop` | 集成分支，各人 PR 的 base |
| `feat/你的部分` | 个人开发分支，一人 review 后合入 `develop` |

**每位成员至少提交一次 PR**，评审会核对仓库中每个人的提交记录。

## 团队

| 学号 | 姓名 | 角色 |
|---|---|---|
| 3224004345 | 翁佳华 | PM / 产品经理 |
| 3224004304 | 胡俐伶 | UI / UX 设计 |
| 3224004307 | 廖颖欣 | 前端负责人 |
| 3224004305 | 柯燕纯 | 后端负责人 |
| 3124004428 | 赖声雄 | 后端（隐私与交易） |
| 3124004447 | 叶浚轩 | 智能体 / AI 工程 |
| 3124004429 | 廖炳程 | 运维 / 部署 + 测试 |

---

*拾集小队 · 2026-11-21*
