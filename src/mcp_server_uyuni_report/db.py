# Copyright (c) 2025 SUSE LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import asyncpg
from pydantic_settings import BaseSettings, SettingsConfigDict
from datetime import date, timedelta
from typing import TypedDict, Union
from enum import Enum
import logging

logger = logging.getLogger(__name__)

class DBSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="DB_", env_file=".env", env_file_encoding="utf-8", extra="ignore")

    hostname: str = "localhost"
    name: str = "reportdb"
    user: str
    password: str
    port: int = 5432

class Granularity(str, Enum):
    DAY = "day"
    WEEK = "week"
    MONTH = "month"
    HALF_YEAR = "half-year"
    YEAR = "year"

class FilterableField(str, Enum):
    ORGANIZATION = "organization"
    SYSTEM_GROUP_NAME = "system_group_name"
    OS_FAMILY = "os_family"
    SEVERITY = "severity"
    ADVISORY_TYPE = "advisory_type"
    HOSTNAME = "hostname"
class ErrataStats(TypedDict):
    mean_time_to_patch: timedelta | None
    mean_time_to_patch_stddev: timedelta | None
    patched_systems_count: int
    created_errata_count: int
    total_affected_systems_count: int
    severity_breakdown: dict[str, int]

class TimeseriesErrataStats(TypedDict):
    time_bucket: date
    mean_time_to_patch: timedelta | None
    patched_systems_count: int
    created_errata_count: int
    total_affected_systems_count: int

def _append_filters(
    conditions: list[str],
    params: list,
    start_date: date | None = None,
    end_date: date | None = None,
    advisory_type: str | None = None,
    advisory_name: str | None = None,
    cve: str | None = None,
    severity: str | None = None,
    hostname: str | None = None,
    os_family: str | None = None,
    organization: str | None = None,
    system_group_name: str | None = None,
    errata_alias: str = "e",
    system_alias: str = "s",
    system_group_alias: str = "sg",
):
    """Appends filter conditions and parameters to the provided lists."""
    if start_date:
        params.append(start_date)
        conditions.append(f"{errata_alias}.issue_date >= ${len(params)}")
    if end_date:
        params.append(end_date)
        conditions.append(f"{errata_alias}.issue_date <= ${len(params)}")
    if advisory_type:
        params.append(advisory_type)
        conditions.append(f"{errata_alias}.advisory_type = ${len(params)}")
    if advisory_name:
        params.append(f"%{advisory_name}%")
        conditions.append(f"{errata_alias}.advisory_name LIKE ${len(params)}")
    if cve:
        params.append(f"%{cve}%")
        conditions.append(f"{errata_alias}.cve LIKE ${len(params)}")
    if severity:
        params.append(severity)
        conditions.append(f"{errata_alias}.severity = ${len(params)}")
    if hostname:
        params.append(f"%{hostname}%")
        conditions.append(f"{system_alias}.hostname LIKE ${len(params)}")
    if os_family:
        params.append(os_family)
        conditions.append(f"{system_alias}.minion_os_family = ${len(params)}")
    if organization:
        params.append(organization)
        conditions.append(f"{system_alias}.organization = ${len(params)}")
    if system_group_name:
        params.append(system_group_name)
        conditions.append(f"{system_group_alias}.name = ${len(params)}")

async def get_errata_stats(
    start_date: date | None = None,
    end_date: date | None = None,
    advisory_type: str | None = None,
    advisory_name: str | None = None,
    cve: str | None = None,
    severity: str | None = None,
    hostname: str | None = None,
    os_family: str | None = None,
    organization: str | None = None,
    system_group_name: str | None = None,
    granularity: Granularity | None = None,
) -> Union[ErrataStats, list[TimeseriesErrataStats]]:
    """
    Calculates errata statistics, either as an aggregate or as a time series.
    """
    settings = DBSettings()
    conn = await asyncpg.connect(
        host=settings.hostname, port=settings.port, database=settings.name, user=settings.user, password=settings.password
    )
    try:
        if granularity:
            # --- Time Series Query (using CTEs for performance) ---
            ts_params = [granularity.value, start_date, end_date]
            ts_conditions: list[str] = []
            _append_filters(ts_conditions, ts_params, start_date, end_date, advisory_type, advisory_name, cve, severity, hostname, os_family, organization, system_group_name)

            created_system_joins = "LEFT JOIN SystemErrata se ON e.errata_id = se.errata_id LEFT JOIN System s ON se.system_id = s.system_id"
            if system_group_name:
                created_system_joins += " LEFT JOIN SystemGroupMember sgm ON s.system_id = sgm.system_id LEFT JOIN SystemGroup sg ON sgm.system_group_id = sg.system_group_id"

            patched_system_joins = "LEFT JOIN System s ON sa.system_id = s.system_id"
            if system_group_name:
                patched_system_joins += " LEFT JOIN SystemGroupMember sgm ON s.system_id = sgm.system_id LEFT JOIN SystemGroup sg ON sgm.system_group_id = sg.system_group_id"

            where_clause = f"WHERE {' AND '.join(ts_conditions)}" if ts_conditions else ""
            patched_where_clause = f"WHERE sa.status = 'Completed' {'AND ' + ' AND '.join(ts_conditions) if ts_conditions else ''}"

            query = f"""
                WITH time_series AS (
                    SELECT generate_series(
                        (CASE WHEN $1 = 'half-year'
                              THEN date_trunc('year', $2::timestamptz) + floor((extract(month from $2::timestamptz) - 1) / 6) * interval '6 month'
                              ELSE date_trunc($1, $2::timestamptz)
                         END),
                        $3::timestamptz,
                        (CASE $1
                            WHEN 'half-year' THEN interval '6 month'
                            ELSE ('1 ' || $1)::interval
                         END)
                    )::date AS time_bucket
                ),
                created AS (
                    SELECT
                        (CASE WHEN $1 = 'half-year'
                              THEN date_trunc('year', e.issue_date) + floor((extract(month from e.issue_date) - 1) / 6) * interval '6 month'
                              ELSE date_trunc($1, e.issue_date)
                         END)::date as time_bucket,
                        count(DISTINCT e.errata_id) as created_errata_count,
                        count(DISTINCT s.system_id) as total_affected_systems_count
                    FROM Errata e
                    {created_system_joins}
                    {where_clause}
                    GROUP BY 1
                ),
                patched AS (
                    SELECT
                        (CASE WHEN $1 = 'half-year'
                              THEN date_trunc('year', sa.completion_time) + floor((extract(month from sa.completion_time) - 1) / 6) * interval '6 month'
                              ELSE date_trunc($1, sa.completion_time)
                         END)::date as time_bucket,
                        count(DISTINCT sa.system_id) as patched_systems_count,
                        avg(AGE(sa.completion_time, e.issue_date)) as mean_time_to_patch
                    FROM SystemAction sa
                    JOIN Errata e ON sa.event_data = e.advisory_name
                    {patched_system_joins}
                    {patched_where_clause}
                    GROUP BY 1
                )
                SELECT
                    ts.time_bucket,
                    COALESCE(p.patched_systems_count, 0) as patched_systems_count,
                    COALESCE(c.created_errata_count, 0) as created_errata_count,
                    COALESCE(c.total_affected_systems_count, 0) as total_affected_systems_count,
                    p.mean_time_to_patch
                FROM time_series ts
                LEFT JOIN created c ON ts.time_bucket = c.time_bucket
                LEFT JOIN patched p ON ts.time_bucket = p.time_bucket
                WHERE ts.time_bucket >= $2 AND ts.time_bucket <= $3
                ORDER BY ts.time_bucket;
            """
            logger.debug("Executing time series query: %s \nPARAMS: %s", query, ts_params)
            rows = await conn.fetch(query, *ts_params)
            return [TimeseriesErrataStats(**row) for row in rows]

        else:
            # --- Aggregate Query ---
            resolution_query_parts = [
                "SELECT avg(AGE(sa.completion_time, e.issue_date)) as mean,",
                "       stddev(EXTRACT(EPOCH FROM AGE(sa.completion_time, e.issue_date))) as stddev,",
                "       count(DISTINCT sa.system_id) as patched_systems_count",
                "FROM SystemAction sa",
                "JOIN Errata e ON sa.event_data = e.advisory_name",
            ]
            resolution_conditions = ["sa.status = 'Completed'"]
            resolution_params: list = []

            system_filters_present = any([hostname, os_family, organization, system_group_name])
            if system_filters_present:
                resolution_query_parts.append("JOIN System s ON sa.system_id = s.system_id")
                if system_group_name:
                    resolution_query_parts.extend(["JOIN SystemGroupMember sgm ON s.system_id = sgm.system_id", "JOIN SystemGroup sg ON sgm.system_group_id = sg.system_group_id"])
            
            _append_filters(resolution_conditions, resolution_params, start_date, end_date, advisory_type, advisory_name, cve, severity, hostname, os_family, organization, system_group_name)
            resolution_query_parts.append(f"WHERE {' AND '.join(resolution_conditions)}")
            resolution_query = " ".join(resolution_query_parts) + ";"
            logger.debug("Executing resolution query: %s \nPARAMS: %s", resolution_query, resolution_params)
            resolution_row = await conn.fetchrow(resolution_query, *resolution_params)

            stats_query_base_parts = ["FROM Errata e"]
            stats_conditions: list[str] = []
            stats_params: list = []
            if system_filters_present:
                stats_query_base_parts.append("JOIN SystemErrata se ON e.errata_id = se.errata_id")
                stats_query_base_parts.append("JOIN System s ON se.system_id = s.system_id")
                if system_group_name:
                    stats_query_base_parts.extend(["JOIN SystemGroupMember sgm ON s.system_id = sgm.system_id", "JOIN SystemGroup sg ON sgm.system_group_id = sg.system_group_id"])

            _append_filters(stats_conditions, stats_params, start_date, end_date, advisory_type, advisory_name, cve, severity, hostname, os_family, organization, system_group_name)
            stats_where_clause = f"WHERE {' AND '.join(stats_conditions)}" if stats_conditions else ""
            stats_base_query = f"{' '.join(stats_query_base_parts)} {stats_where_clause}"

            severity_query = f"SELECT e.severity, count(DISTINCT e.errata_id) as count {stats_base_query} GROUP BY e.severity;"
            logger.debug("Executing severity query: %s \nPARAMS: %s", severity_query, stats_params)
            severity_rows = await conn.fetch(severity_query, *stats_params)
            severity_breakdown = {row['severity']: row['count'] for row in severity_rows if row['severity']}
            created_errata_count = sum(severity_breakdown.values())

            total_systems_query_parts = ["SELECT count(DISTINCT se.system_id) FROM Errata e JOIN SystemErrata se ON e.errata_id = se.errata_id"]
            if system_filters_present:
                total_systems_query_parts.extend(stats_query_base_parts[2:])
            total_systems_query = f"{' '.join(total_systems_query_parts)} {stats_where_clause};"
            logger.debug("Executing total systems query: %s \nPARAMS: %s", total_systems_query, stats_params)
            total_affected_systems_count = await conn.fetchval(total_systems_query, *stats_params) or 0

            patched_systems_count = 0
            mean_time_to_patch = None
            mean_time_to_patch_stddev = None
            if resolution_row and resolution_row["mean"] is not None:
                mean_time_to_patch = resolution_row["mean"]
                if resolution_row["stddev"] is not None:
                    mean_time_to_patch_stddev = timedelta(seconds=float(resolution_row["stddev"]))
                patched_systems_count = resolution_row["patched_systems_count"]

            return ErrataStats(
                mean_time_to_patch=mean_time_to_patch,
                mean_time_to_patch_stddev=mean_time_to_patch_stddev,
                patched_systems_count=patched_systems_count,
                created_errata_count=created_errata_count,
                total_affected_systems_count=total_affected_systems_count,
                severity_breakdown=severity_breakdown,
            )
    finally:
        await conn.close()

async def get_distinct_filter_values(
    field: FilterableField,
    search_term: str | None = None,
    limit: int = 100
) -> list[str]:
    """
    Retrieves distinct values for a given filterable field from the database.
    """
    field_map = {
        FilterableField.ORGANIZATION: ("System", "organization"),
        FilterableField.SYSTEM_GROUP_NAME: ("SystemGroup", "name"),
        FilterableField.OS_FAMILY: ("System", "minion_os_family"),
        FilterableField.SEVERITY: ("Errata", "severity"),
        FilterableField.ADVISORY_TYPE: ("Errata", "advisory_type"),
        FilterableField.HOSTNAME: ("System", "hostname"),
    }

    table, column = field_map[field]

    query_parts = [f"SELECT DISTINCT {column} FROM {table}"]
    params = []
    conditions = [f"{column} IS NOT NULL"]

    if search_term:
        params.append(f"%{search_term}%")
        conditions.append(f"{column} ILIKE ${len(params)}")

    query_parts.append(f"WHERE {' AND '.join(conditions)}")
    query_parts.append(f"ORDER BY {column}")
    
    params.append(limit)
    query_parts.append(f"LIMIT ${len(params)}")
    
    query = " ".join(query_parts) + ";"

    settings = DBSettings()
    conn = await asyncpg.connect(
        host=settings.hostname, port=settings.port, database=settings.name, user=settings.user, password=settings.password
    )
    try:
        logger.debug("Executing distinct filter values query: %s \nPARAMS: %s", query, params)
        rows = await conn.fetch(query, *params)
        return [row[column] for row in rows]
    finally:
        await conn.close()
