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

import os
import logging
import sys
import base64
import io
import matplotlib
# Set non-interactive backend for server-side plotting
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.dates import DateFormatter
from mcp.server.fastmcp import FastMCP, Context
from datetime import date, timedelta, datetime
from typing import Union
from pydantic import BaseModel
from . import db

# Define a safe directory for saving plots
PLOTS_DIR = os.path.abspath("./plots")

mcp = FastMCP("mcp-server-uyuni-report")
@mcp.tool()
async def add(a: int, b: int, ctx: Context) -> int:
    """Add two numbers"""
    return a + b

class ErrataStatsResponse(BaseModel):
    """Statistics about errata."""

    mean_patch_time: str
    mean_patch_time_stddev: str
    patched_systems_count: int
    created_errata_count: int
    total_affected_systems_count: int
    severity_breakdown: dict[str, int]

class TimeseriesDataPoint(BaseModel):
    """
    A single data point in a time series.

    Includes both the real values for labeling and the normalized values (0-1 scale)
    for plotting multiple metrics on the same graph.
    """
    time_bucket: date

    # Real values for labeling
    mean_patch_time: str | None
    patched_systems_count: int
    created_errata_count: int
    total_affected_systems_count: int

    # Normalized values for plotting
    normalized_mean_patch_time: float | None
    normalized_patched_systems_count: float
    normalized_created_errata_count: float
    normalized_total_affected_systems_count: float

class TimeseriesResponse(BaseModel):
    """A full time series response, including the data and max values for context."""
    data: list[TimeseriesDataPoint]
    max_values: dict[str, float]
    info: str = "All values except for time_bucket are normalized to a 0-1 scale by dividing by the max_value for that metric."


@mcp.tool()
async def get_errata_stats(
    ctx: Context,
    start_date: str | None = None,
    end_date: str | None = None,
    advisory_type: str | None = None,
    advisory_name: str | None = None,
    cve: str | None = None,
    severity: str | None = None,
    hostname: str | None = None,
    os_family: str | None = None,
    organization: str | None = None,
    system_group_name: str | None = None,
    granularity: str | None = None,
) -> Union[ErrataStatsResponse, TimeseriesResponse]:
    """
    Calculates statistics about errata. Can return aggregate data or a time series.

    If 'granularity' is provided, this tool returns a time series of statistics,
    suitable for plotting. The returned values are normalized to a 0-1 scale.
    Otherwise, it returns aggregate statistics for the entire period.

    Example Visualization Prompt:
    "Show me a weekly trend of security errata from the beginning of the year until now. Plot the mean patch time, patched systems, and created errata on a graph."

    The tool can be filtered by various optional parameters.
    The database connection parameters must be provided via environment variables:
    - DB_HOSTNAME: The database server hostname (default: localhost).
    - DB_PORT: The database server port (default: 5432).
    - DB_NAME: The database name (default: reportdb).
    - DB_USER: The username for the database connection.
    - DB_PASSWORD: The password for the database connection.

    Filter Parameters:
    - start_date: Filter for errata issued on or after this date (YYYY-MM-DD).
    - end_date: Filter for errata issued on or before this date (YYYY-MM-DD).
    - advisory_type: Filter by advisory type (e.g., 'security', 'bugfix').
    - advisory_name: Filter by advisory name (supports partial matching).
    - cve: Filter by CVE identifier (supports partial matching).
    - severity: Filter by a specific errata severity level.
    - hostname: Filter by system hostname (supports partial matching).
    - os_family: Filter by the OS family of the system (e.g., 'sles').
    - organization: Filter by a specific organization name.
    - system_group_name: Filter by a specific system group name.
    - granularity: If set, returns a time series. Can be 'day', 'week', 'month', 'half-year', or 'year'. Requires start_date and end_date.
    """
    parsed_start_date: date | None = None
    if start_date:
        try:
            parsed_start_date = datetime.strptime(start_date, "%Y-%m-%d").date()
        except ValueError:
            raise ValueError(f"Invalid start_date format: '{start_date}'. Please use YYYY-MM-DD.")

    parsed_end_date: date | None = None
    if end_date:
        try:
            parsed_end_date = datetime.strptime(end_date, "%Y-%m-%d").date()
        except ValueError:
            raise ValueError(f"Invalid end_date format: '{end_date}'. Please use YYYY-MM-DD.")

    parsed_granularity: db.Granularity | None = None
    if granularity:
        if not parsed_start_date or not parsed_end_date:
            raise ValueError("start_date and end_date are required when using granularity.")
        try:
            parsed_granularity = db.Granularity(granularity)
        except ValueError:
            valid_options = ", ".join(g.value for g in db.Granularity)
            raise ValueError(f"Invalid granularity '{granularity}'. Valid options are: {valid_options}")

    stats_data = await db.get_errata_stats(
        start_date=parsed_start_date,
        end_date=parsed_end_date,
        advisory_type=advisory_type,
        advisory_name=advisory_name,
        cve=cve,
        severity=severity,
        hostname=hostname,
        os_family=os_family,
        organization=organization,
        system_group_name=system_group_name,
        granularity=parsed_granularity,
    )

    if isinstance(stats_data, list):
        # Time series case
        if not stats_data:
            return TimeseriesResponse(data=[], max_values={})

        max_patch_time = max((item["mean_time_to_patch"].total_seconds() for item in stats_data if item["mean_time_to_patch"]), default=1.0)
        max_patched_systems = max((item["patched_systems_count"] for item in stats_data), default=1.0)
        max_created_errata = max((item["created_errata_count"] for item in stats_data), default=1.0)
        max_total_affected = max((item["total_affected_systems_count"] for item in stats_data), default=1.0)

        normalized_data = []
        for item in stats_data:
            normalized_time = item["mean_time_to_patch"].total_seconds() / max_patch_time if item["mean_time_to_patch"] else None
            mean_time_str = str(item["mean_time_to_patch"]) if item["mean_time_to_patch"] else None

            normalized_point = TimeseriesDataPoint(
                time_bucket=item["time_bucket"],

                # Real values
                mean_patch_time=mean_time_str,
                patched_systems_count=item["patched_systems_count"],
                created_errata_count=item["created_errata_count"],
                total_affected_systems_count=item["total_affected_systems_count"],

                # Normalized values
                normalized_mean_patch_time=normalized_time,
                normalized_patched_systems_count=item["patched_systems_count"] / max_patched_systems,
                normalized_created_errata_count=item["created_errata_count"] / max_created_errata,
                normalized_total_affected_systems_count=item["total_affected_systems_count"] / max_total_affected,
            )
            normalized_data.append(normalized_point)

        return TimeseriesResponse(data=normalized_data, max_values={"mean_patch_time_seconds": max_patch_time, "patched_systems_count": float(max_patched_systems), "created_errata_count": float(max_created_errata), "total_affected_systems_count": float(max_total_affected)})
    else:
        # Aggregate stats case
        mean_time_str = str(stats_data["mean_time_to_patch"]) if stats_data["mean_time_to_patch"] else "Not enough data to calculate for the given filters."
        stddev_str = str(stats_data["mean_time_to_patch_stddev"]) if stats_data["mean_time_to_patch_stddev"] else "Not applicable (less than 2 data points)."

        return ErrataStatsResponse(mean_patch_time=mean_time_str, mean_patch_time_stddev=stddev_str, patched_systems_count=stats_data["patched_systems_count"], created_errata_count=stats_data["created_errata_count"], total_affected_systems_count=stats_data["total_affected_systems_count"], severity_breakdown=stats_data["severity_breakdown"])

@mcp.tool()
async def get_filter_values(
    ctx: Context,
    field: str,
    search_term: str | None = None,
    limit: int = 100,
) -> list[str]:
    """
    Retrieves a list of possible values for a given filter field.

    This is useful for discovering what organizations, severities, etc. are
    available to filter by in the get_errata_stats tool.

    Parameters:
    - field: The name of the field to get values for.
    - search_term: An optional term to search for within the values (case-insensitive, partial matching).
    - limit: The maximum number of values to return (default: 100).
    """
    try:
        parsed_field = db.FilterableField(field)
    except ValueError:
        valid_options = ", ".join(f.value for f in db.FilterableField)
        raise ValueError(f"Invalid field '{field}'. Valid options are: {valid_options}")

    return await db.get_distinct_filter_values(
        field=parsed_field, search_term=search_term, limit=limit
    )

@mcp.tool()
async def plot_errata_stats_timeseries(
    ctx: Context,
    start_date: str,
    end_date: str,
    granularity: str = "week",
    advisory_type: str | None = None,
    advisory_name: str | None = None,
    cve: str | None = None,
    severity: str | None = None,
    hostname: str | None = None,
    os_family: str | None = None,
    organization: str | None = None,
    system_group_name: str | None = None,
    output_filename: str | None = None,
) -> str:
    """
    Generates and returns a plot image of the errata statistics time series.

    This tool fetches time-series data based on the provided filters and
    generates a PNG image of a line graph. The graph displays the normalized
    trends for mean patch time, patched systems, created errata, and
    total affected systems.

    If 'output_filename' is provided, the plot is saved to that file in the './plots' directory
    and the file path is returned. Otherwise, a base64-encoded string of the PNG image is returned.

    Parameters:
    - start_date: The start date for the time series (YYYY-MM-DD).
    - end_date: The end date for the time series (YYYY-MM-DD).
    - granularity: The time bucket size. Can be 'day', 'week', 'month', 'half-year', or 'year'.
    - output_filename: If provided, saves the plot to this filename (e.g., 'my_report.png').
    - Other filters are the same as the get_errata_stats tool.
    """
    try:
        parsed_start_date = datetime.strptime(start_date, "%Y-%m-%d").date()
    except ValueError:
        raise ValueError(f"Invalid start_date format: '{start_date}'. Please use YYYY-MM-DD.")

    try:
        parsed_end_date = datetime.strptime(end_date, "%Y-%m-%d").date()
    except ValueError:
        raise ValueError(f"Invalid end_date format: '{end_date}'. Please use YYYY-MM-DD.")

    try:
        parsed_granularity = db.Granularity(granularity)
    except ValueError:
        valid_options = ", ".join(g.value for g in db.Granularity)
        raise ValueError(f"Invalid granularity '{granularity}'. Valid options are: {valid_options}")
    stats_data = await db.get_errata_stats(
        start_date=parsed_start_date,
        end_date=parsed_end_date,
        advisory_type=advisory_type,
        advisory_name=advisory_name,
        cve=cve,
        severity=severity,
        hostname=hostname,
        os_family=os_family,
        organization=organization,
        system_group_name=system_group_name,
        granularity=parsed_granularity,
    )

    fig, ax = plt.subplots(figsize=(14, 8))

    if not isinstance(stats_data, list) or not stats_data:
        ax.text(0.5, 0.5, "No data to plot for the given filters.",
                horizontalalignment='center', verticalalignment='center',
                transform=ax.transAxes)
    else:
        time_buckets = [item['time_bucket'] for item in stats_data]
        res_times_sec = [(item['mean_time_to_patch'].total_seconds() if item['mean_time_to_patch'] else 0) for item in stats_data]
        patched_systems = [item['patched_systems_count'] for item in stats_data]
        created_errata = [item['created_errata_count'] for item in stats_data]
        total_affected = [item['total_affected_systems_count'] for item in stats_data]

        max_res_time = max(res_times_sec) or 1.0
        max_patched = max(patched_systems) or 1.0
        max_created = max(created_errata) or 1.0
        max_total = max(total_affected) or 1.0

        ax.plot(time_buckets, [s / max_res_time for s in res_times_sec], label=f'Mean Patch Time (max: {timedelta(seconds=max_res_time)})', marker='o', linestyle='-')
        ax.plot(time_buckets, [s / max_patched for s in patched_systems], label=f'Patched Systems (max: {int(max_patched)})', marker='s', linestyle='-')
        ax.plot(time_buckets, [s / max_created for s in created_errata], label=f'Created Errata (max: {int(max_created)})', marker='^', linestyle='-')
        ax.plot(time_buckets, [s / max_total for s in total_affected], label=f'Total Affected Systems (max: {int(max_total)})', marker='x', linestyle='--')
        if output_filename:
            ax.set_title(f'Err stats {output_filename} ({start_date} to {end_date}', fontsize=16)
        else:
            ax.set_title(f'Errata Statistics Trend ({start_date} to {end_date})', fontsize=16)
        ax.set_xlabel('Time', fontsize=12)
        ax.set_ylabel('Normalized Value (0 to 1)', fontsize=12)
        ax.grid(True, which='both', linestyle='--', linewidth=0.5)
        ax.legend(title="Metrics (Max Values for Scale)")
        ax.xaxis.set_major_formatter(DateFormatter("%Y-%m-%d"))
        fig.autofmt_xdate()

    if output_filename:
        # Security: Basic sanitization of the filename
        if os.path.sep in output_filename or '..' in output_filename:
            raise ValueError("Invalid filename. It cannot contain path separators.")

        os.makedirs(PLOTS_DIR, exist_ok=True)
        full_path = os.path.abspath(os.path.join(PLOTS_DIR, output_filename))

        # Security: Ensure the final path is within the designated PLOTS_DIR
        if not full_path.startswith(PLOTS_DIR):
            raise ValueError("Invalid filename. Path traversal is not allowed.")

        fig.savefig(full_path, format='png', bbox_inches='tight')
        plt.close(fig)
        return f"Plot saved successfully to {full_path}"
    else:
        buf = io.BytesIO()
        fig.savefig(buf, format='png', bbox_inches='tight')
        plt.close(fig)
        buf.seek(0)
        png_bytes = buf.getvalue()
        return base64.b64encode(png_bytes).decode('utf-8')

def main_cli():
    log_level = os.environ.get("LOG_LEVEL", "INFO").upper()
    log_file = os.environ.get("LOG_FILE")

    handlers = [logging.StreamHandler()]  # Defaults to stderr
    if log_file:
        try:
            # Use 'a' for append mode, so logs are not overwritten on restart
            file_handler = logging.FileHandler(log_file, mode='a')
            handlers.append(file_handler)
        except (IOError, OSError) as e:
            # If file logging fails, print an error to stderr and continue with console logging.
            print(f"ERROR: Could not open log file '{log_file}' for writing: {e}", file=sys.stderr)
            handlers = [logging.StreamHandler()]
    
    root_logger = logging.getLogger()
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        handlers=handlers,
        force=True,  # This will remove and re-add handlers, overriding any pre-existing config.
    )
    logging.info("Starting mcp-server-uyuni-report...")
    logging.info(f"Log level set to {log_level}")
    root_logger.info("Effective handlers: %s", handlers)
    mcp.run(transport="stdio")
