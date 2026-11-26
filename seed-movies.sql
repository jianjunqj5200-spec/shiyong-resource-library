-- Curated, official free movie and TV services. Run as the database owner.
-- This script only adds missing listings; it does not alter visitor permissions.
BEGIN;
WITH additions(url, title, description, description_en, category) AS (
  VALUES
    ('https://tubitv.com/', 'Tubi', '免费电影和电视剧，含广告；可观看内容因地区而异。', 'Free movies and TV shows with ads; availability varies by region.', '影视娱乐'),
    ('https://pluto.tv/', 'Pluto TV', '免费电影、电视剧和直播频道，含广告；可观看内容因地区而异。', 'Free movies, shows and live TV channels with ads; availability varies by region.', '影视娱乐'),
    ('https://www.plex.tv/watch-free/', 'Plex Free Movies & TV', '免费观看授权电影、电视剧和直播频道，含广告；片库因地区而异。', 'Watch licensed movies, TV shows and live channels free with ads; titles vary by region.', '影视娱乐'),
    ('https://www.roku.com/whats-on/the-roku-channel', 'The Roku Channel', '提供免费电影、电视剧和直播节目，也有付费订阅；服务因地区而异。', 'Free movies, shows and live TV, with optional paid subscriptions; availability varies by region.', '影视娱乐'),
    ('https://www.kanopy.com/', 'Kanopy', '免费无广告电影与纪录片；需要参与合作的公共图书馆卡或高校账号。', 'Ad-free movies and documentaries with a card from a participating library or a university login.', '影视娱乐'),
    ('https://www.hoopladigital.com/movie', 'hoopla Movies', '凭参与合作的图书馆卡免费借看电影，还可借阅其他数字内容；借阅限制因图书馆而异。', 'Borrow movies and other digital content free with a participating library card; borrowing limits vary by library.', '影视娱乐')
)
INSERT INTO private.resources (submitter_id, url, title, description, description_en, category, status)
SELECT NULL, a.url, a.title, a.description, a.description_en, a.category, 'published'
FROM additions a
WHERE NOT EXISTS (
  SELECT 1 FROM private.resources r
  WHERE lower(rtrim(r.url, '/')) = lower(rtrim(a.url, '/'))
);
COMMIT;
