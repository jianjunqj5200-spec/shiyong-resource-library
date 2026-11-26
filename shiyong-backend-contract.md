# Shiyong Supabase 后端契约与执行步骤

对应迁移文件：[`shiyong-supabase-schema.sql`](shiyong-supabase-schema.sql)。此方案只依赖 Supabase Auth 和 Postgres，不需要在前端复制账号邮箱、用户资料或任何服务密钥。

## 安全模型

业务表位于 `private` schema：资源、断链反馈、管理员 UID 白名单和注册数聚合。所有业务表都启用了 RLS，且**不创建客户端策略**；`anon`、`authenticated` 没有这些表的 schema/table/sequence 权限。前端只能调用下文列出的 `public` RPC。请在 Supabase 的 API 设置中不要把 `private` 加入 Exposed schemas；即使误配置暴露，`private` 的 schema 使用权和表权限仍已撤销。

`SECURITY DEFINER` RPC 固定 `search_path`，以完全限定的 Auth UID 取值及表名执行，并逐个撤销 PostgreSQL 默认授予 `PUBLIC` 的函数执行权，再仅给需要的 Supabase 角色授权。所有投稿人/反馈人 UID 都由 `auth.uid()` 派生，不接受客户端传入的用户 ID。投稿和反馈 RPC 要求已登录；反馈只能针对当前已发布资源。未登录及普通用户不能进入管理函数：每个管理 RPC 都独立验证 UID 是否在私有管理员白名单中。

资源读取 RPC 只返回已发布记录；投稿人只能通过 `my_resource_submissions` 看自己的投稿状态。管理队列返回审核所需内容，但不返回投稿人、反馈人、审核人 UID，也不读取 `auth.users` 邮箱或任何个人资料。管理员授权仅表示可以审核资源/反馈，以及读取唯一注册总数；不授予账号资料查询能力。数据库项目所有者仍可通过 Supabase 后台/SQL 访问 Auth 数据，这是平台级特权，不能由应用迁移消除；不要将该后台权限交给普通内容管理员。

## 部署与管理员 UID 设置

1. 在目标 Supabase 项目的 SQL Editor（或受信任的迁移流程）以数据库 owner，通常为 `postgres`，执行完整的 `shiyong-supabase-schema.sql`。迁移会锁定 `auth.users` 直到触发器与当前用户数基线安装完毕，以避免注册/删除与初始计数竞争。该脚本不需要也不包含项目 URL、JWT、service-role key 或数据库密码。
2. 确认 API 暴露 schema 至少包含 `public`，并且不包含 `private`。前端用项目的正常 Supabase Auth 登录；普通客户端只能使用公开 anon/publishable key。绝不能把 `service_role` key 放进浏览器、移动端包或公开仓库。
3. 先让管理员本人通过 Supabase Auth 注册/登录，再从 Supabase Authentication → Users 或可信 SQL 管理流程取得其 Auth **UID**（UUID）。通过 SQL Editor 执行以下语句，将占位符替换成该 UUID；不要填邮箱：

   ```sql
   INSERT INTO private.admins (user_id)
   VALUES ('<AUTH_USER_UUID>'::uuid)
   ON CONFLICT (user_id) DO NOTHING;
   ```

   撤销管理员权限：`DELETE FROM private.admins WHERE user_id = '<AUTH_USER_UUID>'::uuid;`。白名单表不能由任何前端角色读写；不能通过请求体里的 `is_admin`、metadata、自定义 header 或客户端可写 profile 来授予管理员。若某 UID 尚未对应 Auth 用户，外键会拒绝写入。
4. 部署后按“上线前自查”进行角色测试。迁移的初始统计基于当前 `auth.users` 行数，之后由 Auth 用户新增/删除触发器增减；它是**当前账号数**（含 Auth 表中尚未删除的未确认账号），不是累计注册事件数，也不按邮箱去重。页面仅把此 RPC 的 bigint 当作数字显示。

## 前端 RPC 契约

通过 Supabase JS 的 `supabase.rpc(name, args)` 调用。PostgREST 参数名为下列 `p_*` 字段。登录态请求由 Supabase 客户端携带当前用户 session；不要自己传 user id。未提供邮箱读取、账号列表、profile 读写或直接业务表访问 API。

| RPC | 角色 / 参数 | 返回与用途 |
|---|---|---|
| `published_resources` | `anon`、`authenticated`；`p_limit` 1–100（默认 50），`p_offset` 0–1,000,000（默认 0） | 已发布资源数组：`id,url,title,description,category,created_at`。 |
| `submit_resource` | 仅登录；`p_url,p_title,p_description,p_category` | 返回新资源 UUID；状态固定为 `pending`。网址 10–2048 字符，仅 HTTP(S)，拒绝空白/控制字符、引号/标记字符及 URL userinfo；标题 3–200、描述 1–5000、分类 2–80 字符。前后空白会 trim，表约束仍会复核。 |
| `my_resource_submissions` | 仅登录；无参数 | 当前 UID 自己的投稿和状态；不返回身份字段或内部审核备注。 |
| `report_broken_link` | 仅登录；`p_resource_id` UUID、`p_details` 5–2000 字符 | 返回反馈 UUID。资源必须当前为已发布状态；写入人由 session 确定。 |
| `admin_resource_queue` | 仅登录且管理员；无参数 | 待审核投稿数组，字段为 `id,url,title,description,category,created_at`，没有投稿人资料。 |
| `admin_link_report_queue` | 仅登录且管理员；无参数 | 未处理反馈数组，包含报告/资源 ID、URL、标题、反馈内容和创建时间；不含反馈人资料。 |
| `admin_set_resource_status` | 仅管理员；`p_resource_id`、`p_status`=`pending`/`published`/`rejected`，可选 `p_review_note`（最多 1000 字符） | 更新审核状态及私有审核审计字段；无返回值。 |
| `admin_set_link_report_status` | 仅管理员；`p_report_id`、`p_status`=`open`/`resolved`/`invalid` | 更新反馈处理状态；无返回值。 |
| `admin_registration_count` | 仅管理员；无参数 | 仅返回一个 bigint 当前注册数；无邮箱、用户 ID、列表或其他统计维度。管理界面只呈现此数字。 |

普通用户即使知道上述管理 RPC 名称也不能越权调用：管理 RPC 在数据库端检查管理员表，而不是依赖 UI 隐藏按钮。未登录用户调用写入/管理 RPC 会收到权限错误。前端应将错误当作拒绝处理，不应尝试改用 service role 绕过。

## 上线前自查（建议以真实角色/会话验证）

- `anon`：可调用 `published_resources`；`submit_resource`、`report_broken_link` 与全部管理 RPC 应因没有 EXECUTE 权限或缺少 session 而失败；不得直接 SELECT `private.*`。
- 普通 `authenticated` 用户：投稿/报告成功后，资源仍只在本人投稿查询中显示为 pending；可读公开目录；不能调用私有表，也不能读取别人 pending 记录；所有管理 RPC 和注册统计均返回权限拒绝。
- 白名单管理员：能看待审资源、开放断链反馈、更新状态并读取单个注册总数；队列结果里没有 submitter/reviewer UID、邮箱或 profile 字段。
- 检查 `pg_catalog.pg_class.relrowsecurity` 对四张私有表为 true；`pg_catalog.pg_policies` 对这些表无客户端策略；确认 `anon`、`authenticated` 没有 `private` schema `USAGE`、表 `SELECT/INSERT/UPDATE/DELETE` 或序列权限。检查 public RPC 的 `EXECUTE` 只符合上表授予范围。
- `SECURITY DEFINER` 函数应由可信迁移 owner（通常 `postgres`）持有，并保留脚本中的固定 `search_path`。不要另建同名不安全重载函数，不要向 `PUBLIC` 授予执行权限，不要开启客户端对私有表的宽泛 RLS 策略。
- 若改表/函数，重新检查通过 `auth.uid()` 派生主体、匿名调用、普通用户调用、伪造管理员 UID、分页上界、文本长度和状态枚举。URL 约束是输入边界，不代表可以安全地从服务器抓取该 URL；本应用不得对用户 URL 做无保护的服务端抓取（SSRF 风险）。

这些文件是迁移与接口契约，不会自动部署到 Supabase；当前没有项目引用，本次也未连接任何外部服务。