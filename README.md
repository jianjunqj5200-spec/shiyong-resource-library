# 拾用 Shiyong

一个中英文双语的实用资源导航网站，帮助大家发现、搜索和收藏有用的网站与资料。A bilingual directory for discovering, searching, and saving useful resources.

**在线访问：** https://shiyong-resource-library-final-20261126.plum-jonquil.workers.dev/

## 功能

- 按分类浏览，或按名称、简介、分类和网址搜索资源；支持简体中文和英文。
- 无需登录即可浏览；收藏保存在当前浏览器，不会跨设备同步。
- 访客只能浏览，不能修改资源目录。推荐资源或报告失效链接，请联系 [Telegram @XIAOQU7814](https://t.me/XIAOQU7814)，并附上资源名称、网址和问题说明。
- 部分资源可能有付费计划或使用限制，请以资源提供方的说明为准。

## 本地运行

克隆仓库后，在项目目录运行一个静态文件服务器：

```bash
git clone https://github.com/jianjunqj5200-spec/shiyong-resource-library.git
cd shiyong-resource-library
python3 -m http.server 8000
```

然后访问 [http://localhost:8000](http://localhost:8000)。页面通过网络加载 Supabase 客户端并读取已发布资源，因此需要联网。

前端默认使用当前项目的 Supabase 配置。自行部署时，请在 `index.html` 的 `SUPABASE_CONFIG` 中使用自己的项目 URL 和公开的 publishable/anon key；不要将 `service_role` 或其他秘密密钥放进前端或公开仓库。数据库脚本与部署、安全说明分别见 [`shiyong-supabase-schema.sql`](shiyong-supabase-schema.sql) 和 [`shiyong-backend-contract.md`](shiyong-backend-contract.md)。这些文件不会自动部署，后端契约中的投稿和反馈接口不代表当前网站已开放站内投稿或反馈。

## 许可证

本项目采用 [MIT License](LICENSE)。
