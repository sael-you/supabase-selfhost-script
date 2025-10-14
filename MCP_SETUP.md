# Supabase MCP Server Setup Guide

## What is MCP?

MCP (Model Context Protocol) is a standardized protocol that allows AI assistants like Claude to interact with external tools and services. The Supabase MCP server enables Claude to directly query and manage your Supabase database through natural language.

## Overview

This guide explains how to configure the Supabase MCP server to work with your self-hosted Supabase instance. The MCP server runs locally on your machine and connects to your Supabase API.

## Prerequisites

- Self-hosted Supabase instance running
- Supabase service role key
- Node.js installed (for npx)
- An IDE that supports MCP (Claude Code, Cursor, Windsurf, etc.)

## Configuration

### For Claude Code

Add the following configuration to your `.claude.json` file:

```json
{
  "projects": {
    "/path/to/your/project": {
      "mcpServers": {
        "supabase": {
          "command": "npx",
          "args": [
            "-y",
            "@supabase/mcp-server-postgrest",
            "--apiUrl",
            "https://sbapi.agence-xr.io/rest/v1",
            "--apiKey",
            "YOUR_SERVICE_ROLE_KEY",
            "--schema",
            "public"
          ]
        }
      }
    }
  }
}
```

**Configuration Parameters:**

- `--apiUrl`: Your Supabase REST API endpoint (format: `https://YOUR_DOMAIN/rest/v1`)
- `--apiKey`: Your Supabase service role key (from `.env` file: `SERVICE_ROLE_KEY`)
- `--schema`: PostgreSQL schema to query (usually `public`)

### For Cursor

Add to your Cursor settings (`.cursor/config.json` or settings UI):

```json
{
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": [
        "-y",
        "@supabase/mcp-server-postgrest",
        "--apiUrl",
        "https://sbapi.agence-xr.io/rest/v1",
        "--apiKey",
        "YOUR_SERVICE_ROLE_KEY",
        "--schema",
        "public"
      ]
    }
  }
}
```

### For Windsurf

Add to your Windsurf MCP configuration:

```json
{
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": [
        "-y",
        "@supabase/mcp-server-postgrest",
        "--apiUrl",
        "https://sbapi.agence-xr.io/rest/v1",
        "--apiKey",
        "YOUR_SERVICE_ROLE_KEY",
        "--schema",
        "public"
      ]
    }
  }
}
```

### For Zed Editor

Add to your Zed settings (`~/.config/zed/settings.json`):

```json
{
  "context_servers": {
    "supabase": {
      "command": {
        "path": "npx",
        "args": [
          "-y",
          "@supabase/mcp-server-postgrest",
          "--apiUrl",
          "https://sbapi.agence-xr.io/rest/v1",
          "--apiKey",
          "YOUR_SERVICE_ROLE_KEY",
          "--schema",
          "public"
        ]
      }
    }
  }
}
```

## Getting Your Service Role Key

Your service role key can be found in your Supabase project's `.env` file:

```bash
# Navigate to your project directory
cd /opt/supabase/projects/YOUR_PROJECT_NAME/supabase/docker

# Display the service role key
grep SERVICE_ROLE_KEY .env
```

Or from the deployment output when you created your project.

**⚠️ Security Warning:** The service role key has full access to your database. Never commit it to version control or share it publicly.

## Activation

After adding the configuration:

1. **Restart your IDE completely** (quit and reopen)
2. **Verify connection**:
   - In Claude Code: Type `/mcp` to see available MCP servers
   - In Cursor: Check MCP panel in settings
   - In Windsurf: Check context servers panel

3. **Test the connection**: Ask your AI assistant to query a table:
   ```
   "List all tables in my database"
   "Show me the first 5 rows from the users table"
   ```

## Available MCP Tools

Once configured, you'll have access to:

### 1. `postgrestRequest`
Make direct REST API requests to your database.

**Example usage:**
```
"Use postgrestRequest to get widget_configurations with limit 5"
```

### 2. `sqlToRest`
Convert SQL queries to PostgREST API requests.

**Example usage:**
```
"Convert this SQL to a REST request: SELECT * FROM users WHERE age > 18"
```

## Troubleshooting

### Connection Failed

**Check the logs:**

For Claude Code:
```bash
ls -la ~/Library/Caches/claude-cli-nodejs/-Users-YOUR_USERNAME-YOUR_PROJECT/mcp-logs-supabase/
```

**Common issues:**

1. **"Please provide a base URL with the --apiUrl flag"**
   - Solution: Ensure `--apiUrl` is properly formatted in your config

2. **"Connection closed" / HTTP 401**
   - Solution: Verify your service role key is correct
   - Test API manually:
     ```bash
     curl -H "apikey: YOUR_SERVICE_ROLE_KEY" \
          -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
          https://sbapi.agence-xr.io/rest/v1/
     ```

3. **"Command not found: npx"**
   - Solution: Install Node.js from https://nodejs.org/

4. **Config not loading**
   - Solution: Verify JSON syntax is valid (no trailing commas)
   - Solution: Restart IDE completely (not just reload)

### Testing API Access

Verify your Supabase API is accessible:

```bash
# Test with service role key
curl -H "apikey: YOUR_SERVICE_ROLE_KEY" \
     -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
     https://YOUR_DOMAIN/rest/v1/
```

Should return an OpenAPI schema (JSON response).

## Example Queries

Once MCP is configured, you can ask:

- "List all tables in my database"
- "Show me the schema for the users table"
- "Count how many widget_configurations are active"
- "Get all users created in the last 7 days"
- "Update the widget_enabled field to true for widget ID abc123"
- "Delete all sessions older than 30 days"

## Architecture

```
┌─────────────────┐
│   Your IDE      │
│  (Claude Code)  │
└────────┬────────┘
         │
         ├─ MCP Protocol
         │
         ▼
┌─────────────────────────────┐
│  @supabase/mcp-server       │
│  (runs locally via npx)     │
└────────┬────────────────────┘
         │
         ├─ HTTP REST API
         │
         ▼
┌──────────────────────────────┐
│  Self-hosted Supabase        │
│  https://sbapi.agence-xr.io  │
│  ┌────────────────────────┐  │
│  │  Kong Gateway (8000)   │  │
│  └───────────┬────────────┘  │
│              │                │
│  ┌───────────▼────────────┐  │
│  │  PostgREST (3000)      │  │
│  └───────────┬────────────┘  │
│              │                │
│  ┌───────────▼────────────┐  │
│  │  PostgreSQL (5432)     │  │
│  └────────────────────────┘  │
└──────────────────────────────┘
```

## Configuration for This Project

For this specific self-hosted Supabase instance:

- **API Domain**: `https://sbapi.agence-xr.io`
- **REST API URL**: `https://sbapi.agence-xr.io/rest/v1`
- **Project Name**: `myproject`
- **Schema**: `public`
- **Service Role Key**: Located in `/opt/supabase/projects/myproject/supabase/docker/.env`

## Security Best Practices

1. **Use service role key only in trusted environments** - It bypasses Row Level Security (RLS)
2. **Never commit keys to git** - Add `.claude.json` to `.gitignore` if it contains secrets
3. **Use project-level config** - Consider using `.mcp.json` in project root for shared config (without secrets)
4. **Restrict API access** - Use firewall rules to limit access to your Supabase API
5. **Rotate keys regularly** - Generate new service role keys periodically

## Alternative: Using Environment Variables

Instead of hardcoding the API key in the config, you can use environment variables:

```json
{
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": [
        "-y",
        "@supabase/mcp-server-postgrest",
        "--apiUrl",
        "https://sbapi.agence-xr.io/rest/v1",
        "--apiKey",
        "${SUPABASE_SERVICE_ROLE_KEY}",
        "--schema",
        "public"
      ]
    }
  }
}
```

Then set the environment variable:

```bash
export SUPABASE_SERVICE_ROLE_KEY="your_key_here"
```

## Resources

- [Supabase MCP Documentation](https://supabase.com/docs/guides/getting-started/mcp)
- [PostgREST MCP Server on npm](https://www.npmjs.com/package/@supabase/mcp-server-postgrest)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
- [Claude Code MCP Documentation](https://docs.claude.com/en/docs/claude-code/mcp)

## Support

For issues specific to:
- **Self-hosted Supabase**: Check Docker logs in `/opt/supabase/projects/myproject/supabase/docker/`
- **MCP Server**: Check logs in `~/Library/Caches/claude-cli-nodejs/`
- **Claude Code**: Run `claude --debug` or check GitHub issues

---

**Last Updated**: October 2025
**MCP Server Version**: `@supabase/mcp-server-postgrest@latest`
**Tested With**: Claude Code v2.0.15, Cursor, Windsurf
