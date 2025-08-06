# MCP Uyuni Report Server

This MCP server provides tools to query and analyze data from a Uyuni report database, offering insights into patch management and system compliance.

## Disclaimer
This is an open-source project provided "AS IS" without any warranty, express or implied. Use at your own risk. For full details, please refer to the License section.

## Setup

Before running the server, you must configure the database connection using environment variables.

### Required Environment Variables
*   `DB_USER`: The username for the database connection.
*   `DB_PASSWORD`: The password for the database connection.

### Optional Environment Variables
*   `DB_HOSTNAME`: The database server hostname (default: `localhost`).
*   `DB_PORT`: The database server port (default: `5432`).
*   `DB_NAME`: The database name (default: `reportdb`).

You can set these in your shell or in a `.env` file in the project root.

## Available Tools

### `get_errata_stats`

This is the main tool for retrieving statistics about errata. It can provide either a single aggregate summary or a time-series of data suitable for plotting.

#### Example 1: Getting an Aggregate Summary

> "What are the errata statistics for all 'critical' security advisories in the 'Production Servers' organization during the first quarter of this year?"

#### Example 2: Generating a Time-Series Graph

> "Show me a weekly trend of security errata for my 'sles' systems from the beginning of the year until now. Plot the mean resolution time, patched systems, and created errata on a graph."

### `get_filter_values`

This helper tool allows you to discover the possible values for the various filters in the `get_errata_stats` tool.

#### Example 1: Discovering Available Organizations

> "What organizations can I filter by?"

#### Example 2: Searching for a Specific Hostname

> "Show me available hostnames that contain 'web-server'."

### `plot_errata_stats_timeseries`

This tool directly generates a PNG image of the time-series data, which can be displayed by a capable client.

#### Example

> "Plot a monthly graph of all security errata for the 'Finance' organization over the last year."


## Importing data

In your uyuni server run:
```
podman exec -ti uyuni-server pg_dump --username USERNAME --dbname=reportdb --host=localhost --port=5432 | gzip > test_data.sql.gz
```
Then, copy the test_data.sql.gz into your running directory and 

```
gunzip test_data.sql.gz
```
Then, you can start the postgresql server:
```
./start_uyuni_report_db.sh
```
And load the data
```
./insert_test_data.sh
```

