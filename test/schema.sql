--
-- PostgreSQL database dump
--

-- Dumped from database version 16.9
-- Dumped by pg_dump version 16.9

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: rpm; Type: SCHEMA; Schema: -; Owner: report_db_user
--

CREATE SCHEMA rpm;


ALTER SCHEMA rpm OWNER TO report_db_user;

--
-- Name: create_varnull_constriants(); Type: FUNCTION; Schema: public; Owner: report_db_user
--

CREATE FUNCTION public.create_varnull_constriants() RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
    tabs record;
    total integer default 0;
begin

    for tabs in select 
        c.relname as "tab",
        a.attname as "col"
    from
        pg_catalog.pg_attribute a
        left outer join pg_catalog.pg_class c on a.attrelid = c.oid 
    where
        -- skip system columns
        a.attnum > 0
        -- skip dropped columns
        and not a.attisdropped
        -- filter only varchars
        and a.atttypid = 1043
        -- skip cols that already has this constraint
        and not exists (
            select 1 from pg_catalog.pg_constraint 
            where conname = 'vn_' || c.relname || '_' || a.attname
        )
        -- filter only tables owned by current user
        and a.attrelid in (
            select c.oid from pg_catalog.pg_class c
            where relkind = 'r' and pg_catalog.pg_table_is_visible(c.oid) and relowner = (
                select oid from pg_catalog.pg_roles where rolname = current_user
            )
        ) loop
        begin
            -- create constraint
            execute 'alter table ' || tabs.tab || ' add constraint vn_' ||
                tabs.tab || '_' || tabs.col || ' check (' || tabs.col || ' <> '''')';
            -- count them
        exception when others then
            total = total + 1;
            raise warning '% unable to create constraint for %.%', now(), tabs.tab, tabs.col;
        end;
    end loop;

    return total;
end;
$$;


ALTER FUNCTION public.create_varnull_constriants() OWNER TO report_db_user;

--
-- Name: isalpha(character); Type: FUNCTION; Schema: rpm; Owner: report_db_user
--

CREATE FUNCTION rpm.isalpha(ch character) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
    BEGIN
        if ascii(ch) between ascii('a') and ascii('z') or 
            ascii(ch) between ascii('A') and ascii('Z')
        then
            return TRUE;
        end if;
        return FALSE;
    END;
$$;


ALTER FUNCTION rpm.isalpha(ch character) OWNER TO report_db_user;

--
-- Name: isalphanum(character); Type: FUNCTION; Schema: rpm; Owner: report_db_user
--

CREATE FUNCTION rpm.isalphanum(ch character) RETURNS boolean
    LANGUAGE plpgsql
    AS $$ 
    BEGIN
        if ascii(ch) between ascii('a') and ascii('z') or 
            ascii(ch) between ascii('A') and ascii('Z') or
            ascii(ch) between ascii('0') and ascii('9')
        then
            return TRUE;
        end if;
        return FALSE;
    END;
    $$;


ALTER FUNCTION rpm.isalphanum(ch character) OWNER TO report_db_user;

--
-- Name: isdigit(character); Type: FUNCTION; Schema: rpm; Owner: report_db_user
--

CREATE FUNCTION rpm.isdigit(ch character) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
    BEGIN
        if ascii(ch) between ascii('0') and ascii('9')
        then
            return TRUE;
        end if;
        return FALSE;
    END ;
$$;


ALTER FUNCTION rpm.isdigit(ch character) OWNER TO report_db_user;

--
-- Name: rpmstrcmp(character varying, character varying); Type: FUNCTION; Schema: rpm; Owner: report_db_user
--

CREATE FUNCTION rpm.rpmstrcmp(string1 character varying, string2 character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
    declare
        str1 VARCHAR := string1;
        str2 VARCHAR := string2;
        digits VARCHAR(10) := '0123456789';
        lc_alpha VARCHAR(27) := 'abcdefghijklmnopqrstuvwxyz';
        uc_alpha VARCHAR(27) := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        alpha VARCHAR(54) := lc_alpha || uc_alpha;
        one VARCHAR;
        two VARCHAR;
        isnum BOOLEAN;
    BEGIN
        if str1 is NULL or str2 is NULL
        then
            RAISE EXCEPTION 'VALUE_ERROR.';
        end if;
      
        if str1 = str2
        then
            return 0;
        end if;
        one := str1;
        two := str2;

        <<segment_loop>>
        while one <> '' or two <> ''
        loop
            declare
                segm1 VARCHAR;
                segm2 VARCHAR;
                onechar CHAR(1);
                twochar CHAR(1);
            begin
                --raise notice 'Params: %, %',  one, two;
                -- Throw out all non-alphanum characters
                onechar := substr(one, 1, 1);
                twochar := substr(two, 1, 1);
                while one <> '' and not rpm.isalphanum(one) and onechar != '~' and onechar != '^'
                loop
                    one := substr(one, 2);
                end loop;
                while two <> '' and not rpm.isalphanum(two) and twochar != '~' and twochar != '^'
                loop
                    two := substr(two, 2);
                end loop;
                --raise notice 'new params: %, %', one, two;

                onechar := substr(one, 1, 1);
                twochar := substr(two, 1, 1);
                --raise notice 'new chars 1: %, %', onechar, twochar;
                /* handle the tilde separator, it sorts before everything else */
                if (onechar = '~' or twochar = '~')
                then
                    if (onechar != '~') then return 1; end if;
                    if (twochar != '~') then return -1; end if;
                    --raise notice 'passed tilde chars: %, %', onechar, twochar;
                    one := substr(one, 2);
                    two := substr(two, 2);
                    continue;
                end if;

                /*
                 * Handle caret separator. Concept is the same as tilde,
                 * except that if one of the strings ends (base version),
                 * the other is considered as higher version.
                 */
                onechar := substr(one, 1, 1);
                twochar := substr(two, 1, 1);
                --raise notice 'new chars 2: %, %', onechar, twochar;
                if (onechar = '^' or twochar = '^')
                then
                    if (one = '') then return -1; end if;
                    --raise notice 'passed caret chars 1: %, %', onechar, twochar;
                    if (two = '') then return 1; end if;
                    --raise notice 'passed caret chars 2: %, %', onechar, twochar;
                    if (onechar != '^') then return 1; end if;
                    --raise notice 'passed caret chars 3: %, %', onechar, twochar;
                    if (twochar != '^') then return -1; end if;
                    --raise notice 'passed caret chars 4: %, %', onechar, twochar;
                    one := substr(one, 2);
                    two := substr(two, 2);
                    continue;
                end if;

                if (not (one <> '' and two <> '')) then exit segment_loop; end if;

                str1 := one;
                str2 := two;
                if rpm.isdigit(str1) or rpm.isdigit(str2)
                then
                    str1 := ltrim(str1, digits);
                    str2 := ltrim(str2, digits);
                    isnum := true;
                else
                    str1 := ltrim(str1, alpha);
                    str2 := ltrim(str2, alpha);
                    isnum := false;
                end if;
                if str1 <> ''
                then segm1 := substr(one, 1, length(one) - length(str1));
                else segm1 := one;
                end if;

                if str2 <> ''
                then segm2 := substr(two, 1, length(two) - length(str2));
                else segm2 := two;
                end if;

                if isnum
                then
                    if segm1 = '' then return -1; end if;
                    if segm2 = '' then return 1; end if;

                    segm1 := ltrim(segm1, '0');
                    segm2 := ltrim(segm2, '0');

                    if segm1 = '' and segm2 <> ''
                    then
                        return -1;
                    end if;
                    if segm1 <> '' and segm2 = ''
                    then
                        return 1;
                    end if;
                    if length(segm1) < length(segm2) then return -1; end if;
                    if length(segm1) > length(segm2) then return 1; end if;
                end if;
                if segm1 < segm2 then return -1; end if;
                if segm1 > segm2 then return 1; end if;
               one := str1;
                two := str2;
            end;
        end loop segment_loop;
     
        if one = '' and two = '' then return 0; end if;
        if one = '' then return -1; end if;
        return 1;
    END ;
$$;


ALTER FUNCTION rpm.rpmstrcmp(string1 character varying, string2 character varying) OWNER TO report_db_user;

--
-- Name: vercmp(character varying, character varying, character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: rpm; Owner: report_db_user
--

CREATE FUNCTION rpm.vercmp(e1 character varying, v1 character varying, r1 character varying, e2 character varying, v2 character varying, r2 character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
    declare
        rc INTEGER;
          ep1 INTEGER;
          ep2 INTEGER;
          BEGIN
            if e1 is null or e1 = '' then
              ep1 := 0;
            else
              ep1 := e1::integer;
            end if;
            if e2 is null or e2 = '' then
              ep2 := 0;
            else
              ep2 := e2::integer;
            end if;
            -- Epochs are non-null; compare them
            if ep1 < ep2 then return -1; end if;
            if ep1 > ep2 then return 1; end if;
            rc := rpm.rpmstrcmp(v1, v2);
            if rc != 0 then return rc; end if;
           return rpm.rpmstrcmp(r1, r2);
         END;
         $$;


ALTER FUNCTION rpm.vercmp(e1 character varying, v1 character varying, r1 character varying, e2 character varying, v2 character varying, r2 character varying) OWNER TO report_db_user;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.account (
    mgm_id numeric NOT NULL,
    account_id numeric NOT NULL,
    username character varying(64),
    organization character varying(128),
    last_name character varying(128),
    first_name character varying(128),
    "position" character varying(128),
    email character varying(128),
    creation_time timestamp with time zone,
    last_login_time timestamp with time zone,
    status character varying(32),
    md5_encryption boolean,
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_account_email CHECK (((email)::text <> ''::text)),
    CONSTRAINT vn_account_first_name CHECK (((first_name)::text <> ''::text)),
    CONSTRAINT vn_account_last_name CHECK (((last_name)::text <> ''::text)),
    CONSTRAINT vn_account_organization CHECK (((organization)::text <> ''::text)),
    CONSTRAINT vn_account_position CHECK ((("position")::text <> ''::text)),
    CONSTRAINT vn_account_status CHECK (((status)::text <> ''::text)),
    CONSTRAINT vn_account_username CHECK (((username)::text <> ''::text))
);


ALTER TABLE public.account OWNER TO report_db_user;

--
-- Name: accountgroup; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.accountgroup (
    mgm_id numeric NOT NULL,
    account_id numeric NOT NULL,
    account_group_id numeric NOT NULL,
    username character varying(64),
    account_group_name character varying(64),
    account_group_type_id numeric,
    account_group_type_name character varying(64),
    account_group_type_label character varying(64),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_accountgroup_account_group_name CHECK (((account_group_name)::text <> ''::text)),
    CONSTRAINT vn_accountgroup_account_group_type_label CHECK (((account_group_type_label)::text <> ''::text)),
    CONSTRAINT vn_accountgroup_account_group_type_name CHECK (((account_group_type_name)::text <> ''::text)),
    CONSTRAINT vn_accountgroup_username CHECK (((username)::text <> ''::text))
);


ALTER TABLE public.accountgroup OWNER TO report_db_user;

--
-- Name: accountsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.accountsreport AS
 SELECT account.mgm_id,
    account.organization,
    account.account_id,
    account.username,
    account.last_name,
    account.first_name,
    account."position",
    account.email,
    string_agg((accountgroup.account_group_type_name)::text, ';'::text) AS roles,
    account.creation_time,
    account.last_login_time,
    account.status,
    account.md5_encryption,
    account.synced_date
   FROM (public.account
     LEFT JOIN public.accountgroup ON (((account.mgm_id = accountgroup.mgm_id) AND (account.account_id = accountgroup.account_id))))
  GROUP BY account.mgm_id, account.organization, account.account_id, account.username, account.last_name, account.first_name, account."position", account.email, account.creation_time, account.last_login_time, account.status, account.md5_encryption, account.synced_date
  ORDER BY account.mgm_id, account.organization, account.account_id;


ALTER VIEW public.accountsreport OWNER TO report_db_user;

--
-- Name: system; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.system (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    profile_name character varying(128),
    hostname character varying(128),
    minion_id character varying(256),
    minion_os_family character varying(32),
    minion_kernel_live_version character varying(255),
    machine_id character varying(256),
    registered_by character varying(64),
    registration_time timestamp with time zone,
    last_checkin_time timestamp with time zone,
    kernel_version character varying(64),
    architecture character varying(64),
    is_proxy boolean DEFAULT false NOT NULL,
    proxy_system_id numeric,
    is_mgr_server boolean DEFAULT false NOT NULL,
    organization character varying(128),
    hardware text,
    machine character varying(64),
    rack character varying(64),
    room character varying(32),
    building character varying(128),
    address1 character varying(128),
    address2 character varying(128),
    city character varying(128),
    state character varying(60),
    country character varying(2),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_system_address1 CHECK (((address1)::text <> ''::text)),
    CONSTRAINT vn_system_address2 CHECK (((address2)::text <> ''::text)),
    CONSTRAINT vn_system_architecture CHECK (((architecture)::text <> ''::text)),
    CONSTRAINT vn_system_building CHECK (((building)::text <> ''::text)),
    CONSTRAINT vn_system_city CHECK (((city)::text <> ''::text)),
    CONSTRAINT vn_system_country CHECK (((country)::text <> ''::text)),
    CONSTRAINT vn_system_hostname CHECK (((hostname)::text <> ''::text)),
    CONSTRAINT vn_system_kernel_version CHECK (((kernel_version)::text <> ''::text)),
    CONSTRAINT vn_system_machine CHECK (((machine)::text <> ''::text)),
    CONSTRAINT vn_system_machine_id CHECK (((machine_id)::text <> ''::text)),
    CONSTRAINT vn_system_minion_id CHECK (((minion_id)::text <> ''::text)),
    CONSTRAINT vn_system_minion_kernel_live_version CHECK (((minion_kernel_live_version)::text <> ''::text)),
    CONSTRAINT vn_system_minion_os_family CHECK (((minion_os_family)::text <> ''::text)),
    CONSTRAINT vn_system_organization CHECK (((organization)::text <> ''::text)),
    CONSTRAINT vn_system_profile_name CHECK (((profile_name)::text <> ''::text)),
    CONSTRAINT vn_system_rack CHECK (((rack)::text <> ''::text)),
    CONSTRAINT vn_system_registered_by CHECK (((registered_by)::text <> ''::text)),
    CONSTRAINT vn_system_room CHECK (((room)::text <> ''::text)),
    CONSTRAINT vn_system_state CHECK (((state)::text <> ''::text))
);


ALTER TABLE public.system OWNER TO report_db_user;

--
-- Name: systemgroupmember; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemgroupmember (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    system_group_id numeric NOT NULL,
    group_name character varying(64),
    system_name character varying(128),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemgroupmember_group_name CHECK (((group_name)::text <> ''::text)),
    CONSTRAINT vn_systemgroupmember_system_name CHECK (((system_name)::text <> ''::text))
);


ALTER TABLE public.systemgroupmember OWNER TO report_db_user;

--
-- Name: systemgrouppermission; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemgrouppermission (
    mgm_id numeric NOT NULL,
    system_group_id numeric NOT NULL,
    account_id numeric NOT NULL,
    group_name character varying(64),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemgrouppermission_group_name CHECK (((group_name)::text <> ''::text))
);


ALTER TABLE public.systemgrouppermission OWNER TO report_db_user;

--
-- Name: accountssystemsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.accountssystemsreport AS
 WITH org_admins AS (
         SELECT accountgroup.mgm_id,
            accountgroup.account_id
           FROM public.accountgroup
          WHERE ((accountgroup.account_group_type_label)::text = 'org_admin'::text)
        ), system_users AS (
         SELECT true AS is_admin,
            account.mgm_id,
            account.account_id,
            system.system_id,
            NULL::character varying AS group_name
           FROM (public.system
             JOIN public.account ON (((system.mgm_id = account.mgm_id) AND ((system.organization)::text = (account.organization)::text))))
        UNION
         SELECT false AS is_admin,
            systemgrouppermission.mgm_id,
            systemgrouppermission.account_id,
            systemgroupmember.system_id,
            systemgrouppermission.group_name
           FROM (public.systemgrouppermission
             JOIN public.systemgroupmember ON (((systemgrouppermission.mgm_id = systemgroupmember.mgm_id) AND (systemgrouppermission.system_group_id = systemgroupmember.system_group_id))))
        ), users_details AS (
         SELECT account.mgm_id,
            account.account_id,
            account.username,
            account.organization,
            (org_admins.account_id IS NOT NULL) AS is_admin,
            account.synced_date
           FROM (public.account
             LEFT JOIN org_admins ON (((account.mgm_id = org_admins.mgm_id) AND (account.account_id = org_admins.account_id))))
        )
 SELECT users_details.mgm_id,
    users_details.account_id,
    users_details.username,
    users_details.organization,
    system_users.system_id,
    system_users.group_name,
    users_details.is_admin,
    users_details.synced_date
   FROM (users_details
     LEFT JOIN system_users ON (((users_details.mgm_id = system_users.mgm_id) AND (users_details.is_admin = system_users.is_admin) AND (users_details.account_id = system_users.account_id))))
  WHERE (system_users.system_id IS NOT NULL)
  ORDER BY users_details.mgm_id, users_details.account_id, system_users.system_id;


ALTER VIEW public.accountssystemsreport OWNER TO report_db_user;

--
-- Name: systemaction; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemaction (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    action_id numeric NOT NULL,
    hostname character varying(128),
    scheduler_id numeric,
    scheduler_username character varying(64),
    earliest_action timestamp with time zone,
    archived boolean,
    pickup_time timestamp with time zone,
    completion_time timestamp with time zone,
    action_name character varying(128),
    status character varying(16),
    event character varying(100),
    event_data text,
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemaction_action_name CHECK (((action_name)::text <> ''::text)),
    CONSTRAINT vn_systemaction_event CHECK (((event)::text <> ''::text)),
    CONSTRAINT vn_systemaction_hostname CHECK (((hostname)::text <> ''::text)),
    CONSTRAINT vn_systemaction_scheduler_username CHECK (((scheduler_username)::text <> ''::text)),
    CONSTRAINT vn_systemaction_status CHECK (((status)::text <> ''::text))
);


ALTER TABLE public.systemaction OWNER TO report_db_user;

--
-- Name: actionsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.actionsreport AS
 SELECT DISTINCT mgm_id,
    action_id,
    earliest_action,
    event,
    action_name,
    scheduler_id,
    scheduler_username,
    string_agg((hostname)::text, ';'::text) FILTER (WHERE (((status)::text = 'Picked Up'::text) OR ((status)::text = 'Queued'::text))) OVER (PARTITION BY action_id) AS in_progress_systems,
    string_agg((hostname)::text, ';'::text) FILTER (WHERE ((status)::text = 'Completed'::text)) OVER (PARTITION BY action_id) AS completed_systems,
    string_agg((hostname)::text, ';'::text) FILTER (WHERE ((status)::text = 'Failed'::text)) OVER (PARTITION BY action_id) AS failed_systems,
    archived,
    synced_date
   FROM public.systemaction
  ORDER BY mgm_id, action_id;


ALTER VIEW public.actionsreport OWNER TO report_db_user;

--
-- Name: channel; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.channel (
    mgm_id numeric NOT NULL,
    channel_id numeric NOT NULL,
    name character varying(256),
    label character varying(128),
    type character varying(50),
    arch character varying(64),
    checksum_type character varying(32),
    summary character varying(500),
    description character varying(4000),
    parent_channel_label character varying(128),
    original_channel_id numeric,
    organization character varying(128),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_channel_arch CHECK (((arch)::text <> ''::text)),
    CONSTRAINT vn_channel_checksum_type CHECK (((checksum_type)::text <> ''::text)),
    CONSTRAINT vn_channel_description CHECK (((description)::text <> ''::text)),
    CONSTRAINT vn_channel_label CHECK (((label)::text <> ''::text)),
    CONSTRAINT vn_channel_name CHECK (((name)::text <> ''::text)),
    CONSTRAINT vn_channel_organization CHECK (((organization)::text <> ''::text)),
    CONSTRAINT vn_channel_parent_channel_label CHECK (((parent_channel_label)::text <> ''::text)),
    CONSTRAINT vn_channel_summary CHECK (((summary)::text <> ''::text)),
    CONSTRAINT vn_channel_type CHECK (((type)::text <> ''::text))
);


ALTER TABLE public.channel OWNER TO report_db_user;

--
-- Name: channelerrata; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.channelerrata (
    mgm_id numeric NOT NULL,
    channel_id numeric NOT NULL,
    errata_id numeric NOT NULL,
    channel_label character varying(128),
    advisory_name character varying(100),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_channelerrata_advisory_name CHECK (((advisory_name)::text <> ''::text)),
    CONSTRAINT vn_channelerrata_channel_label CHECK (((channel_label)::text <> ''::text))
);


ALTER TABLE public.channelerrata OWNER TO report_db_user;

--
-- Name: channelpackage; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.channelpackage (
    mgm_id numeric NOT NULL,
    channel_id numeric NOT NULL,
    package_id numeric NOT NULL,
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.channelpackage OWNER TO report_db_user;

--
-- Name: package; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.package (
    mgm_id numeric NOT NULL,
    package_id numeric NOT NULL,
    name character varying(256),
    epoch character varying(16),
    version character varying(512),
    release character varying(512),
    arch character varying(64),
    type character varying(10),
    package_size numeric,
    payload_size numeric,
    installed_size numeric,
    vendor character varying(64),
    organization character varying(128),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_package_arch CHECK (((arch)::text <> ''::text)),
    CONSTRAINT vn_package_epoch CHECK (((epoch)::text <> ''::text)),
    CONSTRAINT vn_package_name CHECK (((name)::text <> ''::text)),
    CONSTRAINT vn_package_organization CHECK (((organization)::text <> ''::text)),
    CONSTRAINT vn_package_release CHECK (((release)::text <> ''::text)),
    CONSTRAINT vn_package_type CHECK (((type)::text <> ''::text)),
    CONSTRAINT vn_package_vendor CHECK (((vendor)::text <> ''::text)),
    CONSTRAINT vn_package_version CHECK (((version)::text <> ''::text))
);


ALTER TABLE public.package OWNER TO report_db_user;

--
-- Name: channelpackagesreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.channelpackagesreport AS
 SELECT channel.mgm_id,
    channel.label AS channel_label,
    channel.name AS channel_name,
    package.name,
    package.version,
    package.release,
    package.epoch,
    package.arch,
    (((((((
        CASE
            WHEN (package.epoch IS NOT NULL) THEN ((package.epoch)::text || ':'::text)
            ELSE ''::text
        END || (package.name)::text) || '-'::text) || (package.version)::text) || '-'::text) || (package.release)::text) || '.'::text) || (package.arch)::text) AS full_package_name,
    package.synced_date
   FROM ((public.channel
     JOIN public.channelpackage ON (((channel.mgm_id = channelpackage.mgm_id) AND (channel.channel_id = channelpackage.channel_id))))
     JOIN public.package ON (((channel.mgm_id = package.mgm_id) AND (channelpackage.package_id = package.package_id))))
  ORDER BY channel.mgm_id, channel.label, package.name, package.version, package.release, package.epoch, package.arch;


ALTER VIEW public.channelpackagesreport OWNER TO report_db_user;

--
-- Name: channelrepository; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.channelrepository (
    mgm_id numeric NOT NULL,
    channel_id numeric NOT NULL,
    repository_id numeric NOT NULL,
    repository_label character varying(128),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_channelrepository_repository_label CHECK (((repository_label)::text <> ''::text))
);


ALTER TABLE public.channelrepository OWNER TO report_db_user;

--
-- Name: channelsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.channelsreport AS
 SELECT channel.mgm_id,
    channel.channel_id,
    channel.label AS channel_label,
    channel.name AS channel_name,
    count(channelpackage.channel_id) AS number_of_packages,
    channel.organization,
    channel.synced_date
   FROM (public.channel
     LEFT JOIN public.channelpackage ON (((channel.mgm_id = channelpackage.mgm_id) AND (channel.channel_id = channelpackage.channel_id))))
  GROUP BY channel.mgm_id, channel.channel_id, channel.label, channel.name, channel.organization, channel.synced_date
  ORDER BY channel.mgm_id, channel.channel_id;


ALTER VIEW public.channelsreport OWNER TO report_db_user;

--
-- Name: clonedchannelsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.clonedchannelsreport AS
 SELECT original.mgm_id,
    original.channel_id AS original_channel_id,
    original.label AS original_channel_label,
    original.name AS original_channel_name,
    cloned.channel_id AS new_channel_id,
    cloned.label AS new_channel_label,
    cloned.name AS new_channel_name,
    cloned.synced_date
   FROM (public.channel original
     JOIN public.channel cloned ON (((cloned.mgm_id = original.mgm_id) AND (cloned.original_channel_id = original.channel_id))))
  ORDER BY original.mgm_id, original.channel_id;


ALTER VIEW public.clonedchannelsreport OWNER TO report_db_user;

--
-- Name: cocoattestation; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.cocoattestation (
    mgm_id numeric NOT NULL,
    report_id numeric NOT NULL,
    system_id numeric NOT NULL,
    action_id numeric NOT NULL,
    environment_type character varying(120),
    status character varying(32),
    create_time timestamp with time zone,
    pass numeric,
    fail numeric,
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_cocoattestation_environment_type CHECK (((environment_type)::text <> ''::text)),
    CONSTRAINT vn_cocoattestation_status CHECK (((status)::text <> ''::text))
);


ALTER TABLE public.cocoattestation OWNER TO report_db_user;

--
-- Name: cocoattestationreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.cocoattestationreport AS
 SELECT cocoattestation.mgm_id,
    cocoattestation.report_id,
    system.system_id,
    cocoattestation.action_id,
    system.hostname,
    system.organization,
    cocoattestation.environment_type,
    cocoattestation.status AS report_status,
    cocoattestation.pass,
    cocoattestation.fail,
    cocoattestation.create_time,
    cocoattestation.synced_date
   FROM (public.cocoattestation
     LEFT JOIN public.system ON (((cocoattestation.mgm_id = system.mgm_id) AND (cocoattestation.system_id = system.system_id))))
  ORDER BY cocoattestation.mgm_id, cocoattestation.report_id, system.system_id, cocoattestation.create_time;


ALTER VIEW public.cocoattestationreport OWNER TO report_db_user;

--
-- Name: cocoattestationresult; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.cocoattestationresult (
    mgm_id numeric NOT NULL,
    report_id numeric NOT NULL,
    result_type_id numeric NOT NULL,
    result_type character varying(128),
    result_status character varying(32),
    description character varying(256),
    details text,
    attestation_time timestamp with time zone,
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_cocoattestationresult_description CHECK (((description)::text <> ''::text)),
    CONSTRAINT vn_cocoattestationresult_result_status CHECK (((result_status)::text <> ''::text)),
    CONSTRAINT vn_cocoattestationresult_result_type CHECK (((result_type)::text <> ''::text))
);


ALTER TABLE public.cocoattestationresult OWNER TO report_db_user;

--
-- Name: cocoattestationresultreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.cocoattestationresultreport AS
 SELECT cocoattestationresult.mgm_id,
    cocoattestationresult.report_id,
    cocoattestationresult.result_type_id,
    system.system_id,
    system.hostname,
    system.organization,
    cocoattestation.environment_type,
    cocoattestationresult.result_type,
    cocoattestationresult.result_status,
    cocoattestationresult.description,
    cocoattestationresult.attestation_time,
    cocoattestationresult.synced_date
   FROM ((public.cocoattestationresult
     LEFT JOIN public.cocoattestation ON (((cocoattestationresult.mgm_id = cocoattestation.mgm_id) AND (cocoattestationresult.report_id = cocoattestation.report_id))))
     LEFT JOIN public.system ON (((cocoattestationresult.mgm_id = system.mgm_id) AND (cocoattestation.system_id = system.system_id))))
  ORDER BY cocoattestationresult.mgm_id, cocoattestationresult.report_id, cocoattestationresult.result_type_id;


ALTER VIEW public.cocoattestationresultreport OWNER TO report_db_user;

--
-- Name: customchannelsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.customchannelsreport AS
 WITH repositories AS (
         SELECT channelrepository.mgm_id,
            channelrepository.channel_id,
            string_agg(((channelrepository.repository_id || ' - '::text) || (channelrepository.repository_label)::text), ';'::text) AS channel_repositories
           FROM public.channelrepository
          GROUP BY channelrepository.mgm_id, channelrepository.channel_id
        )
 SELECT channel.mgm_id,
    channel.organization,
    channel.channel_id,
    channel.label,
    channel.name,
    channel.summary,
    channel.description,
    channel.parent_channel_label,
    channel.arch,
    channel.checksum_type,
    repositories.channel_repositories,
    channel.synced_date
   FROM (public.channel
     LEFT JOIN repositories ON (((channel.mgm_id = repositories.mgm_id) AND (channel.channel_id = repositories.channel_id))))
  WHERE (channel.organization IS NOT NULL)
  ORDER BY channel.mgm_id, channel.organization, channel.channel_id;


ALTER VIEW public.customchannelsreport OWNER TO report_db_user;

--
-- Name: systemcustominfo; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemcustominfo (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    organization character varying(128) NOT NULL,
    key character varying(64) NOT NULL,
    description character varying(4000),
    value character varying(4000),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemcustominfo_description CHECK (((description)::text <> ''::text)),
    CONSTRAINT vn_systemcustominfo_key CHECK (((key)::text <> ''::text)),
    CONSTRAINT vn_systemcustominfo_organization CHECK (((organization)::text <> ''::text)),
    CONSTRAINT vn_systemcustominfo_value CHECK (((value)::text <> ''::text))
);


ALTER TABLE public.systemcustominfo OWNER TO report_db_user;

--
-- Name: custominforeport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.custominforeport AS
 SELECT systemcustominfo.mgm_id,
    systemcustominfo.system_id,
    system.profile_name AS system_name,
    systemcustominfo.organization,
    systemcustominfo.key,
    systemcustominfo.value,
    systemcustominfo.synced_date
   FROM (public.systemcustominfo
     JOIN public.system ON (((systemcustominfo.mgm_id = system.mgm_id) AND (systemcustominfo.system_id = system.system_id))))
  ORDER BY systemcustominfo.mgm_id, systemcustominfo.organization, systemcustominfo.system_id, systemcustominfo.key;


ALTER VIEW public.custominforeport OWNER TO report_db_user;

--
-- Name: dual; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.dual (
    dummy character(1)
);


ALTER TABLE public.dual OWNER TO report_db_user;

--
-- Name: errata; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.errata (
    mgm_id numeric NOT NULL,
    errata_id numeric NOT NULL,
    advisory_name character varying(100),
    advisory_type character varying(32),
    advisory_status character varying(32),
    issue_date timestamp with time zone,
    update_date timestamp with time zone,
    severity character varying(64),
    reboot_required boolean DEFAULT false NOT NULL,
    affects_package_manager boolean DEFAULT false NOT NULL,
    cve text,
    synopsis character varying(4000),
    organization character varying(128),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_errata_advisory_name CHECK (((advisory_name)::text <> ''::text)),
    CONSTRAINT vn_errata_advisory_status CHECK (((advisory_status)::text <> ''::text)),
    CONSTRAINT vn_errata_advisory_type CHECK (((advisory_type)::text <> ''::text)),
    CONSTRAINT vn_errata_cve CHECK ((cve <> ''::text)),
    CONSTRAINT vn_errata_organization CHECK (((organization)::text <> ''::text)),
    CONSTRAINT vn_errata_severity CHECK (((severity)::text <> ''::text)),
    CONSTRAINT vn_errata_synopsis CHECK (((synopsis)::text <> ''::text))
);


ALTER TABLE public.errata OWNER TO report_db_user;

--
-- Name: erratachannelsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.erratachannelsreport AS
 SELECT mgm_id,
    advisory_name,
    errata_id,
    channel_label,
    channel_id,
    synced_date
   FROM public.channelerrata
  ORDER BY mgm_id, advisory_name, errata_id, channel_label, channel_id;


ALTER VIEW public.erratachannelsreport OWNER TO report_db_user;

--
-- Name: systemerrata; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemerrata (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    errata_id numeric NOT NULL,
    hostname character varying(128),
    advisory_name character varying(100),
    advisory_type character varying(32),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemerrata_advisory_name CHECK (((advisory_name)::text <> ''::text)),
    CONSTRAINT vn_systemerrata_advisory_type CHECK (((advisory_type)::text <> ''::text)),
    CONSTRAINT vn_systemerrata_hostname CHECK (((hostname)::text <> ''::text))
);


ALTER TABLE public.systemerrata OWNER TO report_db_user;

--
-- Name: erratalistreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.erratalistreport AS
 SELECT errata.mgm_id,
    errata.errata_id,
    errata.advisory_name,
    errata.advisory_type,
    errata.cve,
    errata.synopsis,
    errata.issue_date,
    errata.update_date,
    count(systemerrata.system_id) AS affected_systems,
    errata.synced_date
   FROM (public.errata
     LEFT JOIN public.systemerrata ON (((errata.mgm_id = systemerrata.mgm_id) AND (errata.errata_id = systemerrata.errata_id))))
  GROUP BY errata.mgm_id, errata.errata_id, errata.advisory_name, errata.advisory_type, errata.cve, errata.synopsis, errata.issue_date, errata.update_date, errata.synced_date
  ORDER BY errata.mgm_id, errata.advisory_name;


ALTER VIEW public.erratalistreport OWNER TO report_db_user;

--
-- Name: systemnetaddressv4; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemnetaddressv4 (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    interface_id numeric NOT NULL,
    address character varying(64) NOT NULL,
    netmask character varying(64),
    broadcast character varying(64),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemnetaddressv4_address CHECK (((address)::text <> ''::text)),
    CONSTRAINT vn_systemnetaddressv4_broadcast CHECK (((broadcast)::text <> ''::text)),
    CONSTRAINT vn_systemnetaddressv4_netmask CHECK (((netmask)::text <> ''::text))
);


ALTER TABLE public.systemnetaddressv4 OWNER TO report_db_user;

--
-- Name: systemnetaddressv6; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemnetaddressv6 (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    interface_id numeric NOT NULL,
    scope character varying(64) NOT NULL,
    address character varying(64) NOT NULL,
    netmask character varying(64),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemnetaddressv6_address CHECK (((address)::text <> ''::text)),
    CONSTRAINT vn_systemnetaddressv6_netmask CHECK (((netmask)::text <> ''::text)),
    CONSTRAINT vn_systemnetaddressv6_scope CHECK (((scope)::text <> ''::text))
);


ALTER TABLE public.systemnetaddressv6 OWNER TO report_db_user;

--
-- Name: systemnetinterface; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemnetinterface (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    interface_id numeric NOT NULL,
    name character varying(32),
    hardware_address character varying(96),
    module character varying(128),
    primary_interface boolean DEFAULT false NOT NULL,
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemnetinterface_hardware_address CHECK (((hardware_address)::text <> ''::text)),
    CONSTRAINT vn_systemnetinterface_module CHECK (((module)::text <> ''::text)),
    CONSTRAINT vn_systemnetinterface_name CHECK (((name)::text <> ''::text))
);


ALTER TABLE public.systemnetinterface OWNER TO report_db_user;

--
-- Name: erratasystemsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.erratasystemsreport AS
 WITH v6addresses AS (
         SELECT systemnetaddressv6.mgm_id,
            systemnetaddressv6.system_id,
            systemnetaddressv6.interface_id,
            string_agg(((((systemnetaddressv6.address)::text || ' ('::text) || (systemnetaddressv6.scope)::text) || ')'::text), ';'::text) AS ip6_addresses
           FROM public.systemnetaddressv6
          GROUP BY systemnetaddressv6.mgm_id, systemnetaddressv6.system_id, systemnetaddressv6.interface_id
        )
 SELECT systemerrata.mgm_id,
    systemerrata.errata_id,
    systemerrata.advisory_name,
    systemerrata.system_id,
    system.profile_name,
    system.hostname,
    systemnetaddressv4.address AS ip_address,
    v6addresses.ip6_addresses,
    systemerrata.synced_date
   FROM ((((public.systemerrata
     JOIN public.system ON (((systemerrata.mgm_id = system.mgm_id) AND (systemerrata.system_id = system.system_id))))
     LEFT JOIN public.systemnetinterface ON (((system.mgm_id = systemnetinterface.mgm_id) AND (system.system_id = systemnetinterface.system_id) AND systemnetinterface.primary_interface)))
     LEFT JOIN public.systemnetaddressv4 ON (((system.mgm_id = systemnetaddressv4.mgm_id) AND (system.system_id = systemnetaddressv4.system_id) AND (systemnetinterface.interface_id = systemnetaddressv4.interface_id))))
     LEFT JOIN v6addresses ON (((system.mgm_id = v6addresses.mgm_id) AND (system.system_id = v6addresses.system_id) AND (systemnetinterface.interface_id = v6addresses.interface_id))))
  ORDER BY systemerrata.mgm_id, systemerrata.errata_id, systemerrata.system_id;


ALTER VIEW public.erratasystemsreport OWNER TO report_db_user;

--
-- Name: systemhistory; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemhistory (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    history_id numeric NOT NULL,
    hostname character varying(128),
    event character varying(100),
    event_data text,
    event_time timestamp with time zone,
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemhistory_event CHECK (((event)::text <> ''::text)),
    CONSTRAINT vn_systemhistory_hostname CHECK (((hostname)::text <> ''::text))
);


ALTER TABLE public.systemhistory OWNER TO report_db_user;

--
-- Name: historyreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.historyreport AS
 SELECT systemaction.mgm_id,
    systemaction.system_id,
    systemaction.action_id AS event_id,
    systemaction.hostname,
    systemaction.event,
    systemaction.completion_time AS event_time,
    systemaction.status,
    systemaction.event_data,
    systemaction.synced_date
   FROM public.systemaction
UNION ALL
 SELECT systemhistory.mgm_id,
    systemhistory.system_id,
    systemhistory.history_id AS event_id,
    systemhistory.hostname,
    systemhistory.event,
    systemhistory.event_time,
    'Done'::character varying AS status,
    systemhistory.event_data,
    systemhistory.synced_date
   FROM public.systemhistory;


ALTER VIEW public.historyreport OWNER TO report_db_user;

--
-- Name: systemvirtualdata; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemvirtualdata (
    mgm_id numeric NOT NULL,
    instance_id numeric NOT NULL,
    host_system_id numeric,
    virtual_system_id numeric,
    name character varying(128),
    instance_type_name character varying(128),
    vcpus numeric,
    memory_size numeric,
    uuid character varying(128),
    confirmed numeric(1,0),
    state_name character varying(128),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemvirtualdata_instance_type_name CHECK (((instance_type_name)::text <> ''::text)),
    CONSTRAINT vn_systemvirtualdata_name CHECK (((name)::text <> ''::text)),
    CONSTRAINT vn_systemvirtualdata_state_name CHECK (((state_name)::text <> ''::text)),
    CONSTRAINT vn_systemvirtualdata_uuid CHECK (((uuid)::text <> ''::text))
);


ALTER TABLE public.systemvirtualdata OWNER TO report_db_user;

--
-- Name: hostguestsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.hostguestsreport AS
 SELECT mgm_id,
    host_system_id AS host,
    virtual_system_id AS guest,
    synced_date
   FROM public.systemvirtualdata
  WHERE ((host_system_id IS NOT NULL) AND (virtual_system_id IS NOT NULL))
  ORDER BY mgm_id, host_system_id, virtual_system_id;


ALTER VIEW public.hostguestsreport OWNER TO report_db_user;

--
-- Name: systemchannel; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemchannel (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    channel_id numeric NOT NULL,
    name character varying(256),
    description character varying(4000),
    architecture_name character varying(64),
    parent_channel_id numeric,
    parent_channel_name character varying(256),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemchannel_architecture_name CHECK (((architecture_name)::text <> ''::text)),
    CONSTRAINT vn_systemchannel_description CHECK (((description)::text <> ''::text)),
    CONSTRAINT vn_systemchannel_name CHECK (((name)::text <> ''::text)),
    CONSTRAINT vn_systemchannel_parent_channel_name CHECK (((parent_channel_name)::text <> ''::text))
);


ALTER TABLE public.systemchannel OWNER TO report_db_user;

--
-- Name: systemconfigchannel; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemconfigchannel (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    config_channel_id numeric NOT NULL,
    name character varying(128),
    "position" numeric,
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemconfigchannel_name CHECK (((name)::text <> ''::text))
);


ALTER TABLE public.systemconfigchannel OWNER TO report_db_user;

--
-- Name: systementitlement; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systementitlement (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    system_group_id numeric NOT NULL,
    name character varying(64),
    description character varying(1024),
    group_type numeric,
    group_type_name character varying(64),
    current_members numeric,
    organization character varying(128),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systementitlement_description CHECK (((description)::text <> ''::text)),
    CONSTRAINT vn_systementitlement_group_type_name CHECK (((group_type_name)::text <> ''::text)),
    CONSTRAINT vn_systementitlement_name CHECK (((name)::text <> ''::text)),
    CONSTRAINT vn_systementitlement_organization CHECK (((organization)::text <> ''::text))
);


ALTER TABLE public.systementitlement OWNER TO report_db_user;

--
-- Name: systemoutdated; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemoutdated (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    packages_out_of_date bigint,
    errata_out_of_date bigint,
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.systemoutdated OWNER TO report_db_user;

--
-- Name: inventoryreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.inventoryreport AS
 WITH entitlements AS (
         SELECT systementitlement.mgm_id,
            systementitlement.system_id,
            string_agg(((systementitlement.system_group_id || ' - '::text) || (systementitlement.name)::text), ';'::text) AS entitlements
           FROM public.systementitlement
          GROUP BY systementitlement.mgm_id, systementitlement.system_id
        ), groups AS (
         SELECT systemgroupmember.mgm_id,
            systemgroupmember.system_id,
            string_agg(((systemgroupmember.system_group_id || ' - '::text) || (systemgroupmember.group_name)::text), ';'::text) AS system_groups
           FROM public.systemgroupmember
          GROUP BY systemgroupmember.mgm_id, systemgroupmember.system_id
        ), configchannels AS (
         SELECT systemconfigchannel.mgm_id,
            systemconfigchannel.system_id,
            string_agg(((systemconfigchannel.config_channel_id || ' - '::text) || (systemconfigchannel.name)::text), ';'::text) AS configuration_channels
           FROM public.systemconfigchannel
          GROUP BY systemconfigchannel.mgm_id, systemconfigchannel.system_id
        ), channels AS (
         SELECT systemchannel.mgm_id,
            systemchannel.system_id,
            string_agg(((systemchannel.channel_id || ' - '::text) || (systemchannel.name)::text), ';'::text) AS software_channels
           FROM public.systemchannel
          GROUP BY systemchannel.mgm_id, systemchannel.system_id
        ), v6addresses AS (
         SELECT systemnetaddressv6.mgm_id,
            systemnetaddressv6.system_id,
            systemnetaddressv6.interface_id,
            string_agg(((((systemnetaddressv6.address)::text || ' ('::text) || (systemnetaddressv6.scope)::text) || ')'::text), ';'::text) AS ip6_addresses
           FROM public.systemnetaddressv6
          GROUP BY systemnetaddressv6.mgm_id, systemnetaddressv6.system_id, systemnetaddressv6.interface_id
        )
 SELECT system.mgm_id,
    system.system_id,
    system.profile_name,
    system.hostname,
    system.minion_id,
    system.machine_id,
    system.registered_by,
    system.registration_time,
    system.last_checkin_time,
    system.kernel_version,
    system.organization,
    system.architecture,
    system.hardware,
    systemnetinterface.name AS primary_interface,
    systemnetinterface.hardware_address,
    systemnetaddressv4.address AS ip_address,
    v6addresses.ip6_addresses,
    configchannels.configuration_channels,
    entitlements.entitlements,
    groups.system_groups,
    systemvirtualdata.host_system_id AS virtual_host,
    (systemvirtualdata.virtual_system_id IS NULL) AS is_virtualized,
    systemvirtualdata.instance_type_name AS virt_type,
    channels.software_channels,
    COALESCE(systemoutdated.packages_out_of_date, (0)::bigint) AS packages_out_of_date,
    COALESCE(systemoutdated.errata_out_of_date, (0)::bigint) AS errata_out_of_date,
    system.synced_date
   FROM (((((((((public.system
     LEFT JOIN public.systemvirtualdata ON (((system.mgm_id = systemvirtualdata.mgm_id) AND (system.system_id = systemvirtualdata.virtual_system_id))))
     LEFT JOIN public.systemoutdated ON (((system.mgm_id = systemoutdated.mgm_id) AND (system.system_id = systemoutdated.system_id))))
     LEFT JOIN public.systemnetinterface ON (((system.mgm_id = systemnetinterface.mgm_id) AND (system.system_id = systemnetinterface.system_id) AND systemnetinterface.primary_interface)))
     LEFT JOIN public.systemnetaddressv4 ON (((system.mgm_id = systemnetaddressv4.mgm_id) AND (system.system_id = systemnetaddressv4.system_id) AND (systemnetinterface.interface_id = systemnetaddressv4.interface_id))))
     LEFT JOIN v6addresses ON (((system.mgm_id = v6addresses.mgm_id) AND (system.system_id = v6addresses.system_id) AND (systemnetinterface.interface_id = v6addresses.interface_id))))
     LEFT JOIN entitlements ON (((system.mgm_id = entitlements.mgm_id) AND (system.system_id = entitlements.system_id))))
     LEFT JOIN groups ON (((system.mgm_id = groups.mgm_id) AND (system.system_id = groups.system_id))))
     LEFT JOIN configchannels ON (((system.mgm_id = configchannels.mgm_id) AND (system.system_id = configchannels.system_id))))
     LEFT JOIN channels ON (((system.mgm_id = channels.mgm_id) AND (system.system_id = channels.system_id))))
  ORDER BY system.mgm_id, system.system_id;


ALTER VIEW public.inventoryreport OWNER TO report_db_user;

--
-- Name: systempackageinstalled; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systempackageinstalled (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    name character varying(256),
    epoch character varying(16),
    version character varying(512),
    release character varying(512),
    arch character varying(64),
    type character varying(10),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systempackageinstalled_arch CHECK (((arch)::text <> ''::text)),
    CONSTRAINT vn_systempackageinstalled_epoch CHECK (((epoch)::text <> ''::text)),
    CONSTRAINT vn_systempackageinstalled_name CHECK (((name)::text <> ''::text)),
    CONSTRAINT vn_systempackageinstalled_release CHECK (((release)::text <> ''::text)),
    CONSTRAINT vn_systempackageinstalled_type CHECK (((type)::text <> ''::text)),
    CONSTRAINT vn_systempackageinstalled_version CHECK (((version)::text <> ''::text))
);


ALTER TABLE public.systempackageinstalled OWNER TO report_db_user;

--
-- Name: systempackageupdate; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systempackageupdate (
    mgm_id numeric NOT NULL,
    system_id numeric NOT NULL,
    package_id numeric NOT NULL,
    name character varying(256),
    epoch character varying(16),
    version character varying(512),
    release character varying(512),
    arch character varying(64),
    type character varying(10),
    is_latest boolean DEFAULT false NOT NULL,
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systempackageupdate_arch CHECK (((arch)::text <> ''::text)),
    CONSTRAINT vn_systempackageupdate_epoch CHECK (((epoch)::text <> ''::text)),
    CONSTRAINT vn_systempackageupdate_name CHECK (((name)::text <> ''::text)),
    CONSTRAINT vn_systempackageupdate_release CHECK (((release)::text <> ''::text)),
    CONSTRAINT vn_systempackageupdate_type CHECK (((type)::text <> ''::text)),
    CONSTRAINT vn_systempackageupdate_version CHECK (((version)::text <> ''::text))
);


ALTER TABLE public.systempackageupdate OWNER TO report_db_user;

--
-- Name: packagesupdatesallreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.packagesupdatesallreport AS
 SELECT system.mgm_id,
    system.system_id,
    system.organization,
    systempackageupdate.name AS package_name,
    systempackageinstalled.epoch AS package_epoch,
    systempackageinstalled.version AS package_version,
    systempackageinstalled.release AS package_release,
    systempackageinstalled.arch AS package_arch,
    systempackageupdate.epoch AS newer_epoch,
    systempackageupdate.version AS newer_version,
    systempackageupdate.release AS newer_release,
    systempackageupdate.synced_date
   FROM ((public.system
     JOIN public.systempackageupdate ON (((system.mgm_id = systempackageupdate.mgm_id) AND (system.system_id = systempackageupdate.system_id))))
     JOIN public.systempackageinstalled ON (((system.mgm_id = systempackageinstalled.mgm_id) AND (system.system_id = systempackageinstalled.system_id) AND ((systempackageinstalled.name)::text = (systempackageupdate.name)::text))))
  ORDER BY system.mgm_id, system.organization, system.system_id, systempackageupdate.name;


ALTER VIEW public.packagesupdatesallreport OWNER TO report_db_user;

--
-- Name: packagesupdatesnewestreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.packagesupdatesnewestreport AS
 SELECT system.mgm_id,
    system.system_id,
    system.organization,
    systempackageupdate.name AS package_name,
    systempackageinstalled.epoch AS package_epoch,
    systempackageinstalled.version AS package_version,
    systempackageinstalled.release AS package_release,
    systempackageinstalled.arch AS package_arch,
    systempackageupdate.epoch AS newer_epoch,
    systempackageupdate.version AS newer_version,
    systempackageupdate.release AS newer_release,
    systempackageupdate.synced_date
   FROM ((public.system
     JOIN public.systempackageupdate ON (((system.mgm_id = systempackageupdate.mgm_id) AND (system.system_id = systempackageupdate.system_id))))
     JOIN public.systempackageinstalled ON (((system.mgm_id = systempackageinstalled.mgm_id) AND (system.system_id = systempackageinstalled.system_id) AND ((systempackageinstalled.name)::text = (systempackageupdate.name)::text))))
  WHERE systempackageupdate.is_latest
  ORDER BY system.mgm_id, system.organization, system.system_id, systempackageupdate.name;


ALTER VIEW public.packagesupdatesnewestreport OWNER TO report_db_user;

--
-- Name: proxyoverviewreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.proxyoverviewreport AS
 SELECT prx.mgm_id,
    prx.system_id AS proxy_id,
    prx.hostname AS proxy_name,
    sys.hostname AS system_name,
    sys.system_id,
    prx.synced_date
   FROM (public.system prx
     JOIN public.system sys ON (((sys.proxy_system_id = prx.system_id) AND (sys.mgm_id = prx.mgm_id))))
  WHERE prx.is_proxy
  ORDER BY prx.mgm_id, prx.system_id, sys.system_id;


ALTER VIEW public.proxyoverviewreport OWNER TO report_db_user;

--
-- Name: repository; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.repository (
    mgm_id numeric NOT NULL,
    repository_id numeric NOT NULL,
    label character varying(128),
    url character varying(2048),
    type character varying(32),
    metadata_signed boolean,
    organization character varying(128),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_repository_label CHECK (((label)::text <> ''::text)),
    CONSTRAINT vn_repository_organization CHECK (((organization)::text <> ''::text)),
    CONSTRAINT vn_repository_type CHECK (((type)::text <> ''::text)),
    CONSTRAINT vn_repository_url CHECK (((url)::text <> ''::text))
);


ALTER TABLE public.repository OWNER TO report_db_user;

--
-- Name: xccdscan; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.xccdscan (
    mgm_id numeric NOT NULL,
    scan_id numeric NOT NULL,
    system_id numeric NOT NULL,
    action_id numeric NOT NULL,
    name character varying(120),
    benchmark character varying(120),
    benchmark_version character varying(80),
    profile character varying(120),
    profile_title character varying(120),
    end_time timestamp with time zone,
    pass numeric,
    fail numeric,
    error numeric,
    not_selected numeric,
    informational numeric,
    other numeric,
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_xccdscan_benchmark CHECK (((benchmark)::text <> ''::text)),
    CONSTRAINT vn_xccdscan_benchmark_version CHECK (((benchmark_version)::text <> ''::text)),
    CONSTRAINT vn_xccdscan_name CHECK (((name)::text <> ''::text)),
    CONSTRAINT vn_xccdscan_profile CHECK (((profile)::text <> ''::text)),
    CONSTRAINT vn_xccdscan_profile_title CHECK (((profile_title)::text <> ''::text))
);


ALTER TABLE public.xccdscan OWNER TO report_db_user;

--
-- Name: scapscanreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.scapscanreport AS
 SELECT xccdscan.mgm_id,
    xccdscan.scan_id,
    system.system_id,
    xccdscan.action_id,
    system.hostname,
    system.organization,
    systemnetaddressv4.address AS ip_address,
    xccdscan.name,
    xccdscan.benchmark,
    xccdscan.benchmark_version,
    xccdscan.profile,
    xccdscan.profile_title,
    xccdscan.end_time,
    xccdscan.pass,
    xccdscan.fail,
    xccdscan.error,
    xccdscan.not_selected,
    xccdscan.informational,
    xccdscan.other,
    xccdscan.synced_date
   FROM (((public.xccdscan
     LEFT JOIN public.system ON (((xccdscan.mgm_id = system.mgm_id) AND (xccdscan.system_id = system.system_id))))
     LEFT JOIN public.systemnetinterface ON (((system.mgm_id = systemnetinterface.mgm_id) AND (system.system_id = systemnetinterface.system_id) AND systemnetinterface.primary_interface)))
     LEFT JOIN public.systemnetaddressv4 ON (((system.mgm_id = systemnetaddressv4.mgm_id) AND (system.system_id = systemnetaddressv4.system_id) AND (systemnetinterface.interface_id = systemnetaddressv4.interface_id))))
  ORDER BY xccdscan.mgm_id, xccdscan.scan_id, system.system_id, xccdscan.end_time;


ALTER VIEW public.scapscanreport OWNER TO report_db_user;

--
-- Name: xccdscanresult; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.xccdscanresult (
    mgm_id numeric NOT NULL,
    scan_id numeric NOT NULL,
    rule_id numeric NOT NULL,
    ident_id numeric NOT NULL,
    idref character varying(255),
    rulesystem character varying(80),
    system_id numeric NOT NULL,
    ident character varying(255),
    result character varying(16),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_xccdscanresult_ident CHECK (((ident)::text <> ''::text)),
    CONSTRAINT vn_xccdscanresult_idref CHECK (((idref)::text <> ''::text)),
    CONSTRAINT vn_xccdscanresult_result CHECK (((result)::text <> ''::text)),
    CONSTRAINT vn_xccdscanresult_rulesystem CHECK (((rulesystem)::text <> ''::text))
);


ALTER TABLE public.xccdscanresult OWNER TO report_db_user;

--
-- Name: scapscanresultreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.scapscanresultreport AS
 SELECT xccdscanresult.mgm_id,
    xccdscanresult.scan_id,
    xccdscanresult.rule_id,
    xccdscanresult.idref,
    xccdscanresult.rulesystem,
    system.system_id,
    system.hostname,
    system.organization,
    xccdscanresult.ident,
    xccdscanresult.result,
    xccdscanresult.synced_date
   FROM (public.xccdscanresult
     LEFT JOIN public.system ON (((xccdscanresult.mgm_id = system.mgm_id) AND (xccdscanresult.system_id = system.system_id))))
  ORDER BY xccdscanresult.mgm_id, xccdscanresult.scan_id, xccdscanresult.rule_id;


ALTER VIEW public.scapscanresultreport OWNER TO report_db_user;

--
-- Name: systemextrapackagesreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.systemextrapackagesreport AS
 WITH packages_from_channels AS (
         SELECT systempackageinstalled_1.mgm_id,
            systempackageinstalled_1.system_id,
            package.package_id,
            systempackageinstalled_1.name,
            systempackageinstalled_1.epoch,
            systempackageinstalled_1.version,
            systempackageinstalled_1.release,
            systempackageinstalled_1.arch,
            systempackageinstalled_1.type
           FROM (((public.systempackageinstalled systempackageinstalled_1
             JOIN public.systemchannel ON (((systempackageinstalled_1.mgm_id = systemchannel.mgm_id) AND (systempackageinstalled_1.system_id = systemchannel.system_id))))
             JOIN public.channelpackage ON (((systemchannel.mgm_id = channelpackage.mgm_id) AND (channelpackage.channel_id = systemchannel.channel_id))))
             JOIN public.package ON (((systempackageinstalled_1.mgm_id = package.mgm_id) AND (channelpackage.package_id = package.package_id) AND ((package.name)::text = (systempackageinstalled_1.name)::text) AND ((COALESCE(package.epoch, ''::character varying))::text = (COALESCE(systempackageinstalled_1.epoch, ''::character varying))::text) AND ((package.version)::text = (systempackageinstalled_1.version)::text) AND ((package.release)::text = (systempackageinstalled_1.release)::text) AND ((package.arch)::text = (systempackageinstalled_1.arch)::text))))
        )
 SELECT system.mgm_id,
    system.system_id,
    system.hostname AS system_name,
    system.organization,
    systempackageinstalled.name AS package_name,
    systempackageinstalled.epoch AS package_epoch,
    systempackageinstalled.version AS package_version,
    systempackageinstalled.release AS package_release,
    systempackageinstalled.arch AS package_arch,
    systempackageinstalled.synced_date
   FROM ((public.system
     JOIN public.systempackageinstalled ON (((system.mgm_id = systempackageinstalled.mgm_id) AND (system.system_id = systempackageinstalled.system_id))))
     LEFT JOIN packages_from_channels ON (((systempackageinstalled.mgm_id = packages_from_channels.mgm_id) AND (systempackageinstalled.system_id = packages_from_channels.system_id) AND ((systempackageinstalled.name)::text = (packages_from_channels.name)::text) AND ((COALESCE(systempackageinstalled.epoch, ''::character varying))::text = (COALESCE(packages_from_channels.epoch, ''::character varying))::text) AND ((systempackageinstalled.version)::text = (packages_from_channels.version)::text) AND ((systempackageinstalled.release)::text = (packages_from_channels.release)::text) AND ((systempackageinstalled.arch)::text = (packages_from_channels.arch)::text))))
  WHERE (packages_from_channels.package_id IS NULL)
  ORDER BY system.mgm_id, system.organization, system.system_id, systempackageinstalled.name;


ALTER VIEW public.systemextrapackagesreport OWNER TO report_db_user;

--
-- Name: systemgroup; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.systemgroup (
    mgm_id numeric NOT NULL,
    system_group_id numeric NOT NULL,
    name character varying(64),
    description character varying(1024),
    current_members numeric,
    organization character varying(128),
    synced_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vn_systemgroup_description CHECK (((description)::text <> ''::text)),
    CONSTRAINT vn_systemgroup_name CHECK (((name)::text <> ''::text)),
    CONSTRAINT vn_systemgroup_organization CHECK (((organization)::text <> ''::text))
);


ALTER TABLE public.systemgroup OWNER TO report_db_user;

--
-- Name: systemgroupsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.systemgroupsreport AS
 SELECT mgm_id,
    system_group_id,
    name,
    current_members,
    organization,
    synced_date
   FROM public.systemgroup
  ORDER BY mgm_id, system_group_id;


ALTER VIEW public.systemgroupsreport OWNER TO report_db_user;

--
-- Name: systemgroupssystemsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.systemgroupssystemsreport AS
 SELECT systemgroupmember.mgm_id,
    systemgroupmember.system_group_id AS group_id,
    systemgroupmember.group_name,
    system.system_id,
    system.profile_name AS system_name,
    systemgroupmember.synced_date
   FROM (public.systemgroupmember
     JOIN public.system ON (((systemgroupmember.mgm_id = system.mgm_id) AND (systemgroupmember.system_id = system.system_id))))
  ORDER BY systemgroupmember.mgm_id, systemgroupmember.system_group_id, systemgroupmember.system_id;


ALTER VIEW public.systemgroupssystemsreport OWNER TO report_db_user;

--
-- Name: systemhistoryautoinstallationreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.systemhistoryautoinstallationreport AS
 SELECT mgm_id,
    system_id,
    action_id,
    earliest_action,
    pickup_time,
    completion_time,
    status,
    event,
    event_data,
    synced_date
   FROM public.systemaction
  WHERE ((event)::text = ANY (ARRAY[('Schedule a package sync for auto installations'::character varying)::text, ('Initiate an auto installation'::character varying)::text]))
  ORDER BY mgm_id, system_id, action_id;


ALTER VIEW public.systemhistoryautoinstallationreport OWNER TO report_db_user;

--
-- Name: systemhistorychannelsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.systemhistorychannelsreport AS
 SELECT mgm_id,
    system_id,
    history_id,
    event_time,
    'Done'::text AS status,
    event,
    event_data,
    synced_date
   FROM public.systemhistory
  WHERE ((event)::text = ANY (ARRAY[('Subscribed to channel'::character varying)::text, ('Unsubscribed from channel'::character varying)::text]))
  ORDER BY mgm_id, system_id, history_id;


ALTER VIEW public.systemhistorychannelsreport OWNER TO report_db_user;

--
-- Name: systemhistoryconfigurationreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.systemhistoryconfigurationreport AS
 SELECT mgm_id,
    system_id,
    action_id,
    earliest_action,
    pickup_time,
    completion_time,
    status,
    event,
    event_data,
    synced_date
   FROM public.systemaction
  WHERE ((event)::text = ANY (ARRAY[('Upload config file data to server'::character varying)::text, ('Verify deployed config files'::character varying)::text, ('Show differences between profiled config files and deployed config files'::character varying)::text, ('Upload config file data based upon mtime to server'::character varying)::text, ('Deploy config files to system'::character varying)::text]))
  ORDER BY mgm_id, system_id, action_id;


ALTER VIEW public.systemhistoryconfigurationreport OWNER TO report_db_user;

--
-- Name: systemhistoryentitlementsreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.systemhistoryentitlementsreport AS
 SELECT mgm_id,
    system_id,
    history_id,
    event_time,
    'Done'::text AS status,
    event,
    event_data,
    synced_date
   FROM public.systemhistory
  WHERE ((event)::text <> ALL (ARRAY[('Subscribed to channel'::character varying)::text, ('Unsubscribed from channel'::character varying)::text]))
  ORDER BY mgm_id, system_id, history_id;


ALTER VIEW public.systemhistoryentitlementsreport OWNER TO report_db_user;

--
-- Name: systemhistoryerratareport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.systemhistoryerratareport AS
 SELECT mgm_id,
    system_id,
    action_id,
    earliest_action,
    pickup_time,
    completion_time,
    status,
    event,
    event_data,
    synced_date
   FROM public.systemaction
  WHERE ((event)::text = 'Patch Update'::text)
  ORDER BY mgm_id, system_id, action_id;


ALTER VIEW public.systemhistoryerratareport OWNER TO report_db_user;

--
-- Name: systemhistorypackagesreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.systemhistorypackagesreport AS
 SELECT mgm_id,
    system_id,
    action_id,
    earliest_action,
    pickup_time,
    completion_time,
    status,
    event,
    event_data,
    synced_date
   FROM public.systemaction
  WHERE ((event)::text = ANY (ARRAY[('Package Upgrade'::character varying)::text, ('Package Removal'::character varying)::text]))
  ORDER BY mgm_id, system_id, action_id;


ALTER VIEW public.systemhistorypackagesreport OWNER TO report_db_user;

--
-- Name: systemhistoryscapreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.systemhistoryscapreport AS
 SELECT mgm_id,
    system_id,
    action_id,
    earliest_action,
    pickup_time,
    completion_time,
    status,
    event,
    event_data,
    synced_date
   FROM public.systemaction
  WHERE ((event)::text = 'OpenSCAP xccdf scanning'::text)
  ORDER BY mgm_id, system_id, action_id;


ALTER VIEW public.systemhistoryscapreport OWNER TO report_db_user;

--
-- Name: systeminactivityreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.systeminactivityreport AS
 SELECT mgm_id,
    system_id,
    profile_name AS system_name,
    organization,
    last_checkin_time,
    (synced_date - last_checkin_time) AS inactivity,
    synced_date
   FROM public.system
  ORDER BY mgm_id, system_id, organization;


ALTER VIEW public.systeminactivityreport OWNER TO report_db_user;

--
-- Name: systempackagesinstalledreport; Type: VIEW; Schema: public; Owner: report_db_user
--

CREATE VIEW public.systempackagesinstalledreport AS
 SELECT systempackageinstalled.mgm_id,
    systempackageinstalled.system_id,
    system.organization,
    systempackageinstalled.name AS package_name,
    systempackageinstalled.epoch AS package_epoch,
    systempackageinstalled.version AS package_version,
    systempackageinstalled.release AS package_release,
    systempackageinstalled.arch AS package_arch,
    systempackageinstalled.synced_date
   FROM (public.systempackageinstalled
     JOIN public.system ON ((system.system_id = systempackageinstalled.system_id)))
  ORDER BY systempackageinstalled.mgm_id, systempackageinstalled.system_id, systempackageinstalled.name;


ALTER VIEW public.systempackagesinstalledreport OWNER TO report_db_user;

--
-- Name: versioninfo; Type: TABLE; Schema: public; Owner: report_db_user
--

CREATE TABLE public.versioninfo (
    name character varying(256) NOT NULL,
    label character varying(64) NOT NULL,
    version character varying(512) NOT NULL,
    release character varying(512) NOT NULL,
    created timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT vn_versioninfo_label CHECK (((label)::text <> ''::text)),
    CONSTRAINT vn_versioninfo_name CHECK (((name)::text <> ''::text)),
    CONSTRAINT vn_versioninfo_release CHECK (((release)::text <> ''::text)),
    CONSTRAINT vn_versioninfo_version CHECK (((version)::text <> ''::text))
);


ALTER TABLE public.versioninfo OWNER TO report_db_user;

--
-- Name: account account_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.account
    ADD CONSTRAINT account_pk PRIMARY KEY (mgm_id, account_id);


--
-- Name: accountgroup accountgroup_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.accountgroup
    ADD CONSTRAINT accountgroup_pk PRIMARY KEY (mgm_id, account_id, account_group_id);


--
-- Name: channel channel_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.channel
    ADD CONSTRAINT channel_pk PRIMARY KEY (mgm_id, channel_id);


--
-- Name: channelerrata channelerrata_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.channelerrata
    ADD CONSTRAINT channelerrata_pk PRIMARY KEY (mgm_id, channel_id, errata_id);


--
-- Name: channelpackage channelpackage_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.channelpackage
    ADD CONSTRAINT channelpackage_pk PRIMARY KEY (mgm_id, channel_id, package_id);


--
-- Name: channelrepository channelrepository_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.channelrepository
    ADD CONSTRAINT channelrepository_pk PRIMARY KEY (mgm_id, channel_id, repository_id);


--
-- Name: cocoattestation cocoattestation_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.cocoattestation
    ADD CONSTRAINT cocoattestation_pk PRIMARY KEY (mgm_id, report_id);


--
-- Name: cocoattestationresult cocoattestationresult_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.cocoattestationresult
    ADD CONSTRAINT cocoattestationresult_pk PRIMARY KEY (mgm_id, report_id, result_type_id);


--
-- Name: errata errata_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.errata
    ADD CONSTRAINT errata_pk PRIMARY KEY (mgm_id, errata_id);


--
-- Name: package package_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.package
    ADD CONSTRAINT package_pk PRIMARY KEY (mgm_id, package_id);


--
-- Name: repository repository_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.repository
    ADD CONSTRAINT repository_pk PRIMARY KEY (mgm_id, repository_id);


--
-- Name: system system_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.system
    ADD CONSTRAINT system_pk PRIMARY KEY (mgm_id, system_id);


--
-- Name: systemaction systemaction_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemaction
    ADD CONSTRAINT systemaction_pk PRIMARY KEY (mgm_id, system_id, action_id);


--
-- Name: systemchannel systemchannel_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemchannel
    ADD CONSTRAINT systemchannel_pk PRIMARY KEY (mgm_id, system_id, channel_id);


--
-- Name: systemconfigchannel systemconfigchannel_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemconfigchannel
    ADD CONSTRAINT systemconfigchannel_pk PRIMARY KEY (mgm_id, system_id, config_channel_id);


--
-- Name: systemcustominfo systemcustominfo_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemcustominfo
    ADD CONSTRAINT systemcustominfo_pk PRIMARY KEY (mgm_id, organization, system_id, key);


--
-- Name: systementitlement systementitlement_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systementitlement
    ADD CONSTRAINT systementitlement_pk PRIMARY KEY (mgm_id, system_id, system_group_id);


--
-- Name: systemerrata systemerrata_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemerrata
    ADD CONSTRAINT systemerrata_pk PRIMARY KEY (mgm_id, system_id, errata_id);


--
-- Name: systemgroup systemgroup_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemgroup
    ADD CONSTRAINT systemgroup_pk PRIMARY KEY (mgm_id, system_group_id);


--
-- Name: systemgroupmember systemgroupmember_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemgroupmember
    ADD CONSTRAINT systemgroupmember_pk PRIMARY KEY (mgm_id, system_id, system_group_id);


--
-- Name: systemgrouppermission systemgrouppermission_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemgrouppermission
    ADD CONSTRAINT systemgrouppermission_pk PRIMARY KEY (mgm_id, system_group_id, account_id);


--
-- Name: systemhistory systemhistory_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemhistory
    ADD CONSTRAINT systemhistory_pk PRIMARY KEY (mgm_id, system_id, history_id);


--
-- Name: systemnetaddressv4 systemnetaddressv4_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemnetaddressv4
    ADD CONSTRAINT systemnetaddressv4_pk PRIMARY KEY (mgm_id, system_id, interface_id, address);


--
-- Name: systemnetaddressv6 systemnetaddressv6_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemnetaddressv6
    ADD CONSTRAINT systemnetaddressv6_pk PRIMARY KEY (mgm_id, system_id, interface_id, scope, address);


--
-- Name: systemnetinterface systemnetinterface_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemnetinterface
    ADD CONSTRAINT systemnetinterface_pk PRIMARY KEY (mgm_id, system_id, interface_id);


--
-- Name: systemoutdated systemoutdated_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemoutdated
    ADD CONSTRAINT systemoutdated_pk PRIMARY KEY (mgm_id, system_id);


--
-- Name: systempackageupdate systempackageupdate_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systempackageupdate
    ADD CONSTRAINT systempackageupdate_pk PRIMARY KEY (mgm_id, system_id, package_id);


--
-- Name: systemvirtualdata systemvirtualdata_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.systemvirtualdata
    ADD CONSTRAINT systemvirtualdata_pk PRIMARY KEY (mgm_id, instance_id);


--
-- Name: xccdscan xccdscan_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.xccdscan
    ADD CONSTRAINT xccdscan_pk PRIMARY KEY (mgm_id, scan_id);


--
-- Name: xccdscanresult xccdscanresult_pk; Type: CONSTRAINT; Schema: public; Owner: report_db_user
--

ALTER TABLE ONLY public.xccdscanresult
    ADD CONSTRAINT xccdscanresult_pk PRIMARY KEY (mgm_id, scan_id, rule_id, ident_id);


--
-- Name: system_profile_name_idx; Type: INDEX; Schema: public; Owner: report_db_user
--

CREATE INDEX system_profile_name_idx ON public.system USING btree (profile_name);


--
-- Name: systempackageinstalled_order_idx; Type: INDEX; Schema: public; Owner: report_db_user
--

CREATE INDEX systempackageinstalled_order_idx ON public.systempackageinstalled USING btree (mgm_id, system_id, name, epoch, version, release, arch, type);


--
-- Name: versioninfo_name_label_uq; Type: INDEX; Schema: public; Owner: report_db_user
--

CREATE UNIQUE INDEX versioninfo_name_label_uq ON public.versioninfo USING btree (name, label);


--
-- Name: dual deny_delete_dual; Type: RULE; Schema: public; Owner: report_db_user
--

CREATE RULE deny_delete_dual AS
    ON DELETE TO public.dual DO INSTEAD NOTHING;


--
-- Name: dual deny_insert_dual; Type: RULE; Schema: public; Owner: report_db_user
--

CREATE RULE deny_insert_dual AS
    ON INSERT TO public.dual DO INSTEAD NOTHING;


--
-- Name: dual deny_update_dual; Type: RULE; Schema: public; Owner: report_db_user
--

CREATE RULE deny_update_dual AS
    ON UPDATE TO public.dual DO INSTEAD NOTHING;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO report_db_user;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

