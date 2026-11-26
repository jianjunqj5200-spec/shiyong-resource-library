-- Shiyong resource library: least-privilege Supabase schema and RPC contract.
-- Apply as the Supabase database owner (normally `postgres`) in a transaction.
-- No auth email/profile fields are copied into this application schema.
-- All frontend data access is through the explicitly granted public RPC functions below.

BEGIN;

-- Keep the initial count and trigger installation consistent with concurrent signups.
LOCK TABLE auth.users IN SHARE ROW EXCLUSIVE MODE;

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS private.admins (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE TABLE IF NOT EXISTS private.resources (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    submitter_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    url text NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    category text NOT NULL,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'published', 'rejected')),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    reviewed_at timestamptz,
    reviewer_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    review_note text,
    CONSTRAINT resources_url_length CHECK (pg_catalog.length(url) BETWEEN 10 AND 2048),
    CONSTRAINT resources_url_scheme CHECK (url ~* '^https?://[^/?#]+'),
    CONSTRAINT resources_url_no_whitespace_or_markup CHECK (url !~ '[[:space:][:cntrl:]<>"]'),
    CONSTRAINT resources_url_no_single_quote CHECK (pg_catalog.strpos(url, pg_catalog.chr(39)) = 0),
    CONSTRAINT resources_url_no_userinfo CHECK (
        pg_catalog.split_part(pg_catalog.split_part(url, '://', 2), '/', 1) !~ '@'
    ),
    CONSTRAINT resources_title_length CHECK (
        title = pg_catalog.btrim(title) AND pg_catalog.length(title) BETWEEN 3 AND 200
    ),
    CONSTRAINT resources_description_length CHECK (
        description = pg_catalog.btrim(description) AND pg_catalog.length(description) BETWEEN 1 AND 5000
    ),
    CONSTRAINT resources_category_length CHECK (
        category = pg_catalog.btrim(category) AND pg_catalog.length(category) BETWEEN 2 AND 80
    ),
    CONSTRAINT resources_review_note_length CHECK (
        review_note IS NULL OR pg_catalog.length(review_note) <= 1000
    )
);

CREATE INDEX IF NOT EXISTS resources_publication_idx
    ON private.resources (created_at DESC) WHERE status = 'published';
CREATE INDEX IF NOT EXISTS resources_moderation_idx
    ON private.resources (created_at ASC) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS resources_submitter_idx
    ON private.resources (submitter_id, created_at DESC);

CREATE TABLE IF NOT EXISTS private.link_reports (
    id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
    resource_id uuid NOT NULL REFERENCES private.resources(id) ON DELETE CASCADE,
    submitter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    details text NOT NULL,
    status text NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'resolved', 'invalid')),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    reviewed_at timestamptz,
    reviewer_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    CONSTRAINT link_reports_details_length CHECK (
        details = pg_catalog.btrim(details) AND pg_catalog.length(details) BETWEEN 5 AND 2000
    )
);
CREATE INDEX IF NOT EXISTS link_reports_moderation_idx
    ON private.link_reports (created_at ASC) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS link_reports_resource_idx
    ON private.link_reports (resource_id, created_at DESC);

-- One row only; the value is a current account count, not an event/history count.
CREATE TABLE IF NOT EXISTS private.registration_stats (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    user_count bigint NOT NULL CHECK (user_count >= 0),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

-- RLS is on for every private data table. No client policies are intentionally
-- defined: direct API access is denied; narrowly scoped owner-run RPCs are the only path.
ALTER TABLE private.admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.link_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.registration_stats ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, private, auth
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM private.admins AS a WHERE a.user_id = auth.uid()
    );
$function$;
REVOKE ALL ON FUNCTION private.is_admin() FROM PUBLIC, anon, authenticated;

-- Count new/deleted Auth accounts without storing any email or profile attributes.
CREATE OR REPLACE FUNCTION private.auth_user_count_delta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, private
AS $function$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO private.registration_stats (singleton, user_count, updated_at)
        VALUES (true, 1, pg_catalog.now())
        ON CONFLICT (singleton) DO UPDATE
          SET user_count = private.registration_stats.user_count + 1,
              updated_at = pg_catalog.now();
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE private.registration_stats
           SET user_count = CASE WHEN user_count > 0 THEN user_count - 1 ELSE 0 END,
               updated_at = pg_catalog.now()
         WHERE singleton = true;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION private.auth_user_count_delta() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS shiyong_auth_user_count_insert ON auth.users;
CREATE TRIGGER shiyong_auth_user_count_insert
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION private.auth_user_count_delta();
DROP TRIGGER IF EXISTS shiyong_auth_user_count_delete ON auth.users;
CREATE TRIGGER shiyong_auth_user_count_delete
AFTER DELETE ON auth.users
FOR EACH ROW EXECUTE FUNCTION private.auth_user_count_delta();

-- Lock above prevents signup/delete races while the baseline is initialized.
INSERT INTO private.registration_stats (singleton, user_count, updated_at)
SELECT true, pg_catalog.count(*)::bigint, pg_catalog.now() FROM auth.users
ON CONFLICT (singleton) DO UPDATE
   SET user_count = EXCLUDED.user_count,
       updated_at = EXCLUDED.updated_at;

-- Public, non-sensitive catalog. The result intentionally omits submitter/reviewer IDs.
CREATE OR REPLACE FUNCTION public.published_resources(
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS TABLE (
    id uuid,
    url text,
    title text,
    description text,
    category text,
    created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, private, auth
AS $function$
BEGIN
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100
       OR p_offset IS NULL OR p_offset < 0 OR p_offset > 1000000 THEN
        RAISE EXCEPTION 'invalid pagination' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    SELECT r.id, r.url, r.title, r.description, r.category, r.created_at
      FROM private.resources AS r
     WHERE r.status = 'published'
     ORDER BY r.created_at DESC, r.id
     LIMIT p_limit OFFSET p_offset;
END;
$function$;

-- Authenticated user submission; owner identity is derived only from the JWT.
CREATE OR REPLACE FUNCTION public.submit_resource(
    p_url text,
    p_title text,
    p_description text,
    p_category text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, private, auth
AS $function$
DECLARE
    v_user_id uuid := auth.uid();
    v_id uuid;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
    END IF;
    IF p_url IS NULL OR p_title IS NULL OR p_description IS NULL OR p_category IS NULL THEN
        RAISE EXCEPTION 'all resource fields are required' USING ERRCODE = '22023';
    END IF;
    INSERT INTO private.resources (submitter_id, url, title, description, category)
    VALUES (v_user_id, pg_catalog.btrim(p_url), pg_catalog.btrim(p_title),
            pg_catalog.btrim(p_description), pg_catalog.btrim(p_category))
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$function$;

-- User submissions are visible only to their authenticated submitter; no profile/email fields.
CREATE OR REPLACE FUNCTION public.my_resource_submissions()
RETURNS TABLE (
    id uuid,
    url text,
    title text,
    description text,
    category text,
    status text,
    created_at timestamptz,
    reviewed_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, private, auth
AS $function$
DECLARE
    v_user_id uuid := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT r.id, r.url, r.title, r.description, r.category, r.status,
           r.created_at, r.reviewed_at
      FROM private.resources AS r
     WHERE r.submitter_id = v_user_id
     ORDER BY r.created_at DESC;
END;
$function$;

-- A report can target only a currently published catalog entry.
CREATE OR REPLACE FUNCTION public.report_broken_link(
    p_resource_id uuid,
    p_details text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, private, auth
AS $function$
DECLARE
    v_user_id uuid := auth.uid();
    v_report_id uuid;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
    END IF;
    IF p_resource_id IS NULL OR p_details IS NULL THEN
        RAISE EXCEPTION 'resource and report details are required' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM private.resources AS r
         WHERE r.id = p_resource_id AND r.status = 'published'
    ) THEN
        RAISE EXCEPTION 'published resource not found' USING ERRCODE = '22023';
    END IF;
    INSERT INTO private.link_reports (resource_id, submitter_id, details)
    VALUES (p_resource_id, v_user_id, pg_catalog.btrim(p_details))
    RETURNING id INTO v_report_id;
    RETURN v_report_id;
END;
$function$;

-- Admin queues omit submitter/reviewer identifiers and all Auth/profile data.
CREATE OR REPLACE FUNCTION public.admin_resource_queue()
RETURNS TABLE (
    id uuid,
    url text,
    title text,
    description text,
    category text,
    created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, private, auth
AS $function$
BEGIN
    IF NOT private.is_admin() THEN
        RAISE EXCEPTION 'administrator authorization required' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT r.id, r.url, r.title, r.description, r.category, r.created_at
      FROM private.resources AS r
     WHERE r.status = 'pending'
     ORDER BY r.created_at ASC, r.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_link_report_queue()
RETURNS TABLE (
    id uuid,
    resource_id uuid,
    resource_url text,
    resource_title text,
    details text,
    created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, private, auth
AS $function$
BEGIN
    IF NOT private.is_admin() THEN
        RAISE EXCEPTION 'administrator authorization required' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT lr.id, r.id, r.url, r.title, lr.details, lr.created_at
      FROM private.link_reports AS lr
      JOIN private.resources AS r ON r.id = lr.resource_id
     WHERE lr.status = 'open'
     ORDER BY lr.created_at ASC, lr.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_resource_status(
    p_resource_id uuid,
    p_status text,
    p_review_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, private, auth
AS $function$
DECLARE
    v_admin_id uuid := auth.uid();
BEGIN
    IF v_admin_id IS NULL OR NOT private.is_admin() THEN
        RAISE EXCEPTION 'administrator authorization required' USING ERRCODE = '42501';
    END IF;
    IF p_resource_id IS NULL OR p_status IS NULL OR p_status NOT IN ('pending', 'published', 'rejected')
       OR (p_review_note IS NOT NULL AND pg_catalog.length(pg_catalog.btrim(p_review_note)) > 1000) THEN
        RAISE EXCEPTION 'invalid moderation input' USING ERRCODE = '22023';
    END IF;
    UPDATE private.resources AS r
       SET status = p_status,
           updated_at = pg_catalog.now(),
           reviewed_at = pg_catalog.now(),
           reviewer_id = v_admin_id,
           review_note = NULLIF(pg_catalog.btrim(COALESCE(p_review_note, '')), '')
     WHERE r.id = p_resource_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'resource not found' USING ERRCODE = '22023';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_set_link_report_status(
    p_report_id uuid,
    p_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, private, auth
AS $function$
DECLARE
    v_admin_id uuid := auth.uid();
BEGIN
    IF v_admin_id IS NULL OR NOT private.is_admin() THEN
        RAISE EXCEPTION 'administrator authorization required' USING ERRCODE = '42501';
    END IF;
    IF p_report_id IS NULL OR p_status IS NULL OR p_status NOT IN ('open', 'resolved', 'invalid') THEN
        RAISE EXCEPTION 'invalid moderation input' USING ERRCODE = '22023';
    END IF;
    UPDATE private.link_reports AS lr
       SET status = p_status,
           updated_at = pg_catalog.now(),
           reviewed_at = pg_catalog.now(),
           reviewer_id = v_admin_id
     WHERE lr.id = p_report_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'report not found' USING ERRCODE = '22023';
    END IF;
END;
$function$;

-- Single aggregate only; never expose auth.users, email, or profile attributes.
CREATE OR REPLACE FUNCTION public.admin_registration_count()
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, private, auth
AS $function$
DECLARE
    v_count bigint;
BEGIN
    IF auth.uid() IS NULL OR NOT private.is_admin() THEN
        RAISE EXCEPTION 'administrator authorization required' USING ERRCODE = '42501';
    END IF;
    SELECT s.user_count INTO v_count
      FROM private.registration_stats AS s
     WHERE s.singleton = true;
    RETURN COALESCE(v_count, 0);
END;
$function$;

-- Functions are executable by PUBLIC by default in PostgreSQL; revoke first,
-- then grant only the exact RPCs to the required client roles.
REVOKE ALL ON FUNCTION public.published_resources(integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_resource(text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.my_resource_submissions() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.report_broken_link(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_resource_queue() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_link_report_queue() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_resource_status(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_link_report_status(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_registration_count() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.published_resources(integer, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_resource(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_resource_submissions() TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_broken_link(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_resource_queue() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_link_report_queue() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_resource_status(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_link_report_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_registration_count() TO authenticated;

COMMENT ON SCHEMA private IS 'Not an API schema; all application access is via explicitly granted public RPCs.';
COMMENT ON TABLE private.admins IS 'Privileged UID allowlist; change only via trusted SQL administration.';
COMMENT ON TABLE private.registration_stats IS 'Aggregate current Auth account count only; contains no personal data.';

COMMIT;
