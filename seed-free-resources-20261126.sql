-- Verified free/open resources for the Shiyong read-only catalog.
-- Run as a trusted database owner; never expose database credentials to visitors.
BEGIN;
WITH candidates(url,title,description,description_en,category) AS (VALUES
  ('https://www.theodinproject.com/', 'The Odin Project', '免费全栈 Web 开发自学课程，包含学习路线、实践项目与社区；课程内容以非商业许可发布。', 'Free self-paced full-stack web development curriculum with learning paths, projects and community support; course content is licensed for non-commercial use.', '学习资料'),
  ('https://phet.colorado.edu/', 'PhET Interactive Simulations', '免费的物理、数学、化学等互动学习模拟；常规模拟限非商业用途，分享须署名。', 'Free interactive simulations for physics, math, chemistry and more; standard simulations are for non-commercial use and require attribution when shared.', '学习资料'),
  ('https://www.gutenberg.org/', 'Project Gutenberg', '免费在线阅读或下载经典电子书；版权状态因国家地区及作品而异，请先查看许可。', 'Read or download classic e-books for free; copyright varies by work and country, so check the applicable license.', '学习资料'),
  ('https://unsplash.com/', 'Unsplash', '可搜索的免费照片与插画；标准素材依 Unsplash 许可使用，Unsplash+ 另需订阅。', 'Search free photos and illustrations under the Unsplash license; Unsplash+ content requires a separate subscription.', '设计灵感'),
  ('https://www.pexels.com/', 'Pexels', '免费下载照片与视频，可用于个人和商业项目；请遵守素材许可及人物、商标等权利。', 'Download free photos and videos for personal and commercial projects; respect the license and any personality or trademark rights.', '设计灵感'),
  ('https://www.svgrepo.com/', 'SVG Repo', '搜索和下载 SVG 图标、矢量图及插画；各素材许可不同，使用前请逐项核对。', 'Search and download SVG icons, vectors and illustrations; licenses vary by asset, so check each item before use.', '设计灵感'),
  ('https://squoosh.app/', 'Squoosh', '免费图片压缩与格式转换工具，图片处理在浏览器本地进行；网站会收集基本使用统计。', 'Free browser-based image compression and conversion; image processing happens locally, while the site collects basic usage analytics.', '日常工具'),
  ('https://exercism.org/', 'Exercism', '免费编程练习平台，提供多种语言的习题、自动分析和导师反馈；提交内容的公开与许可规则请查看设置。', 'Free programming exercises across many languages with automated analysis and mentor feedback; check privacy settings and licenses for submitted work.', '学习资料'),
  ('https://devdocs.io/', 'DevDocs', '免费开源的开发文档搜索工具，整合多个 API 文档并支持可选离线阅读；文档授权各异。', 'Free open-source search across API documentation with optional offline reading; licenses vary by documentation source.', '开发工具'),
  ('https://mermaid.live/', 'Mermaid Live Editor', '免费开源的 Mermaid 图表在线编辑器，可预览与导出流程图等；分享及外部渲染时避免填写敏感信息。', 'Free open-source online editor to preview and export Mermaid diagrams; avoid sensitive content when sharing or using external rendering.', '开发工具'),
  ('https://www.blender.org/', 'Blender', '免费开源的三维创作软件，支持建模、动画、渲染等，核心软件可用于商业或教育用途。', 'Free, open-source 3D creation software for modeling, animation and rendering; the core software may be used commercially or for education.', '开源项目'),
  ('https://inkscape.org/', 'Inkscape', '免费开源的矢量图形编辑软件，可制作插画、图标、标志和示意图，支持多种桌面系统。', 'Free, open-source vector graphics editor for illustrations, icons, logos and diagrams on major desktop platforms.', '开源项目'),
  ('https://www.audacityteam.org/', 'Audacity', '免费开源桌面音频工具，可录音、剪辑和混音；可选在线服务可能收费。', 'Free, open-source desktop audio software for recording, editing and mixing; optional online services may cost extra.', '开源项目'),
  ('https://kdenlive.org/', 'Kdenlive', '免费开源的视频剪辑软件，支持多轨时间线、转场、效果、标题和字幕。', 'Free, open-source video editing software with a multitrack timeline, transitions, effects, titles and subtitles.', '开源项目')
)
INSERT INTO private.resources (submitter_id,url,title,description,description_en,category,status)
SELECT NULL,c.url,c.title,c.description,c.description_en,c.category,'published' FROM candidates AS c
WHERE NOT EXISTS (SELECT 1 FROM private.resources AS r WHERE lower(rtrim(r.url,'/'))=lower(rtrim(c.url,'/')));
COMMIT;
