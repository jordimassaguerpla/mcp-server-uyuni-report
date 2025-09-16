# MCP Uyuni Report Server

This MCP server provides tools to query and analyze data from a Uyuni report database, offering insights into patch management and system compliance.

## Disclaimer
This is an open-source project provided "AS IS" without any warranty, express or implied. Use at your own risk. For full details, please refer to the License section.

## Available Tools

* get_errata_stats
* get_filter_values
* plot_errata_stats_timeseries

### `get_errata_stats`

This is the main tool for retrieving statistics about errata. It can provide either a single aggregate summary or a time-series of data suitable for plotting.

#### Example 1: Getting an Aggregate Summary

> "What are the errata statistics for all 'critical' security advisories in the 'Production Servers' organization during the first quarter of this year?"

#### Example 2: Generating a Time-Series Graph

> "Show me a weekly trend of security errata for my 'sles' systems from the beginning of the year until now. Plot the mean patch time, patched systems, and created errata on a graph."

#### Filter Examples

You can use various filters to narrow down your query. Here are examples for each filter individually and how to combine them.

##### Individual Filters

*   **Date Range**:
    *   `start_date`: "What are the errata statistics for patches issued since the start of 2024?"
    *   `end_date`: "Show me errata stats for patches issued before July 1st, 2023."
*   **Advisory Properties**:
    *   `advisory_type`: "Get me the stats for all 'bugfix' advisories."
    *   `advisory_name`: "What are the stats for advisories with 'kernel' in their name?"
    *   `cve`: "Find statistics for the errata related to 'CVE-2023-12345'."
    *   `severity`: "What are the statistics for all 'moderate' severity errata?"
*   **System Properties**:
    *   `hostname`: "Show me errata statistics for systems with 'db-server' in their hostname."
    *   `os_family`: "Get statistics for all 'rhel' systems."
    *   `organization`: "What are the errata stats for the 'Human Resources' organization?"
    *   `system_group_name`: "Show me the statistics for the 'PCI-Compliance' system group."
*   **Output Format**:
    *   `granularity`: "Show me a monthly trend of all errata from the beginning of the year until now."

##### Combining Filters

Filters can be combined to create highly specific queries.

*   **Aggregate Example**:
    > "What are the aggregate statistics for 'critical' security patches related to CVEs containing '2024' that affect 'sles' systems in the 'Finance' organization?"

*   **Time-Series Example**:
    > "Show me a weekly trend of 'important' security errata for systems in the 'Web Servers' group, from the beginning of the year until now."

*   **Complex Aggregate Example**:
    > "Calculate the mean time to resolution for 'bugfix' advisories with 'samba' in their name, applied to systems in the 'File Servers' group within the 'Engineering' organization, for patches issued in the last 6 months."

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

## Running with an MCP Client

To use this server with an MCP client (such as `mcp-host`, `gemini-cli`, `openwebui`, etc.), you need to configure the client to know how to start the `mcp-server-uyuni-report` process. This is done by creating a `config.json` file in your client's configuration directory.

This server requires its own configuration to connect to the database. This can be provided via a separate configuration file (e.g., `.env` or `config`) containing environment variables.

### Configuration

The server is configured using environment variables. These can be placed in a file (e.g., `config` or `.env`) that is then passed to the `uv` or `docker` command.

#### Required Environment Variables
*   `DB_USER`: The username for the database connection.
*   `DB_PASSWORD`: The password for the database connection.

#### Optional Environment Variables
*   `DB_HOSTNAME`: The database server hostname (default: `localhost`).
*   `DB_PORT`: The database server port (default: `5432`).
*   `DB_NAME`: The database name (default: `reportdb`).
*   `LOG_FILE`: Path to a file where logs will be written (e.g., `/var/log/mcp-uyuni-report.log`). If not set, logs are written to standard error.
*   `LOG_LEVEL`: The logging level for the application (e.g., `DEBUG`, `INFO`, `WARNING`). Default: `INFO`.

### Method 1: Using `uv` (Local Development)

This method runs the server directly on your machine using `uv`.

1.  **Create a server configuration file** with the necessary environment variables for the database connection. For example, create a file named `config` in the project root:

    ```bash
    # File: /path/to/mcp-server-uyuni-report/config
    DB_USER="your_db_user"
    DB_PASSWORD="your_db_password"
    DB_HOSTNAME="localhost"
    DB_NAME="reportdb"
    LOG_LEVEL="DEBUG"
    ```

2.  **Create a client `config.json` file**. This file tells your MCP client how to launch the server using `uv` and where to find the server's configuration file.

    **Example `config.json` for your client:**
    ```json
    {
      "mcpServers": {
        "mcp-server-uyuni-report": {
          "command": "uv",
          "args": [
            "run",
            "--env-file=/path/to/mcp-server-uyuni-report/config",
            "--directory",
            "/path/to/mcp-server-uyuni-report",
            "mcp-server-uyuni-report"
          ]
        }
      }
    }
    ```
    *   Replace `/path/to/mcp-server-uyuni-report` with the absolute path to this project's directory.

### Method 2: Using a Container (Docker/Podman)

This method runs the server inside a container, which is ideal for production or isolated environments. The setup is similar, but the client's `config.json` will use `docker` or `podman` to run the server.

1.  **Create the server configuration file** as described in the `uv` method above.

2.  **Create a client `config.json` file** that instructs the client to launch a container.

    **Example `config.json` for your client:**
    ```json
    {
      "mcpServers": {
        "mcp-server-uyuni-report": {
          "command": "docker",
          "args": [
            "run", "--rm", "-i",
            "--env-file", "/path/to/mcp-server-uyuni-report/config",
            "mcp-uyuni-report-server:latest"
          ]
        }
      }
    }
    ```
    *   This assumes you have built a Docker image named `mcp-uyuni-report-server:latest`.
    *   Ensure the path to the `--env-file` is correct and accessible from where the client is run.

## Using a local database

The recommended workflow is to start a local database and import the data from a reportdb dump. This way, the MCP Server does not need direct access to the reportdb database.

### Staring the database

You can start the postgresql server:
```
./start_uyuni_report_db.sh
```

### Importing data

In your uyuni server run:
```
podman exec -ti uyuni-server pg_dump --username USERNAME --dbname=reportdb --host=localhost --port=5432 | gzip > test_data.sql.gz
```
Then, copy the test_data.sql.gz into your running directory and 

```
gunzip test_data.sql.gz
```

And load the data
```
./insert_test_data.sh test_data.sql
```
## Feedback

We would love to hear from you! Any idea you want to discuss or share, please do so at [https://github.com/uyuni-project/uyuni/discussions/10562](https://github.com/uyuni-project/uyuni/disc
ussions/10562)

If you encounter any bug, be so kind to open a new bug report at [https://github.com/uyuni-project/mcp-server-uyuni/issues/new?type=bug](https://github.com/uyuni-project/mcp-server-uyuni/is
sues/new?type=bug)

Thanks in advance from the uyuni team!

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for details.
