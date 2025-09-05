-- This script is designed to be idempotent. It clears existing data before inserting the new set.
SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET escape_string_warning = off;
SET row_security = off;

-- Populate SystemGroup
COPY public.SystemGroup (mgm_id, system_group_id, name) FROM stdin;
1	1	production-servers
1	2	PCI-Compliance
1	3	Web Servers
1	4	File Servers
1	5	Test Group
\.

-- Populate System
COPY public.System (mgm_id, system_id, hostname, minion_os_family, organization, registration_time) FROM stdin;
1	1	my-server-01	sles	SUSE	2022-01-01
1	2	sles-generic-01	sles	SUSE	2022-01-02
1	3	rhel-generic-01	rhel	Red Hat	2022-02-01
1	4	prod-db-01	sles	Finance	2022-03-01
1	5	web-server-rhel-01	rhel	Finance	2022-03-02
1	6	test-host-1	sles	Test Org	2023-01-01
\.

-- Populate SystemGroupMember
COPY public.SystemGroupMember (mgm_id, system_group_id, system_id) FROM stdin;
1	1	4
1	3	5
1	5	6
\.

-- Populate Errata
COPY public.Errata (mgm_id, errata_id, advisory_name, advisory_type, issue_date, severity, cve) FROM stdin;
1	101	SUSE-BF-2023:0615-1	bugfix	2023-06-15	moderate	\N
1	102	SUSE-EN-2023:0820-1	enhancement	2023-08-20	low	\N
1	103	RHEL-SA-2023:1101-1	security	2023-11-01	important	CVE-2023-5555
1	201	SUSE-SU-2024:1234-1	security	2024-01-10	critical	CVE-2024-0001,CVE-2024-0002
1	202	SUSE-SU-2024:0201-1	security	2024-02-01	critical	CVE-2024-1111
1	203	RHEL-SA-2024:0301-1	security	2024-03-01	important	CVE-2024-1234
1	204	SUSE-BF-2024:0315-1	bugfix	2024-03-15	low	\N
\.

-- Populate SystemErrata (Affected Systems)
COPY public.SystemErrata (mgm_id, system_id, errata_id) FROM stdin;
1	1	101
1	2	102
1	3	103
1	5	103
1	1	201
1	2	201
1	4	201
1	2	202
1	3	203
1	5	203
1	6	204
\.

-- Populate SystemAction (Patched Systems)
COPY public.SystemAction (mgm_id, action_id, system_id, event_data, completion_time, status) FROM stdin;
1	1	1	SUSE-BF-2023:0615-1	2023-06-20 10:00:00	Completed
1	2	3	RHEL-SA-2023:1101-1	2023-11-05 12:00:00	Completed
1	3	1	SUSE-SU-2024:1234-1	2024-01-12 08:00:00	Completed
1	4	4	SUSE-SU-2024:1234-1	2024-01-15 09:00:00	Completed
1	5	2	SUSE-SU-2024:0201-1	2024-02-11 14:00:00	Completed
1	6	3	RHEL-SA-2024:0301-1	2024-03-03 16:00:00	Completed
1	7	5	RHEL-SA-2024:0301-1	2024-03-03 16:00:00	Pending
\.
