# Self-Hosted Supabase Deployment Script

Complete automation script for deploying self-hosted Supabase instances with custom domains, SMTP configuration, and branded email templates.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment Script Usage](#deployment-script-usage)
- [Email Templates](#email-templates)
- [MCP Server Setup](#mcp-server-setup)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)
- [Security](#security)

## Overview

This repository contains a production-ready deployment script for self-hosted Supabase instances. It automates the entire setup process including:

- Multi-project isolation with port management
- Custom domain configuration
- SMTP email integration
- Branded HTML email templates
- SSL/TLS support via reverse proxy (Plesk/Nginx)
- MCP (Model Context Protocol) integration for AI assistants

## Features

- **🚀 Automated Deployment**: One-command deployment of complete Supabase stack
- **🔒 Multi-Project Isolation**: Run multiple Supabase instances on the same server
- **📧 SMTP Integration**: Built-in email authentication with customizable templates
- **🎨 Branded Email Templates**: Professional HTML email templates with your branding
- **🤖 MCP Support**: AI assistant integration for database management
- **🔐 Secure by Default**: URL-encoded passwords, service role keys, RLS support
- **🌐 Custom Domains**: Easy configuration with reverse proxy support
- **📊 Port Management**: Automatic port allocation and conflict detection

## Prerequisites

**Server Requirements:**
- Linux server (Ubuntu 20.04+ recommended)
- Docker & Docker Compose installed
- Git installed
- Python 3 installed
- Root or sudo access
- Minimum 2GB RAM, 20GB disk space

**Optional:**
- Reverse proxy (Plesk, Nginx, Caddy) for SSL/TLS
- SMTP server credentials for email functionality
- Custom domain names

**Installation Commands:**
```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Install Docker Compose (if not included)
sudo apt-get install docker-compose-plugin

# Install Git and Python
sudo apt-get update
sudo apt-get install -y git python3
```

## Quick Start

### 1. Clone the Repository

```bash
# Clone to a permanent location (recommended: /root/supabase-script/)
sudo mkdir -p /root/supabase-script
cd /root/supabase-script
git clone https://github.com/sael-you/supabase-selfhost-script.git .
chmod +x script.sh
```

### 2. Deploy Your First Instance

**Basic deployment (without SMTP):**
```bash
sudo ./script.sh myproject api.example.com studio.example.com
```

**Full deployment with SMTP:**
```bash
sudo ./script.sh myproject \
  api.example.com \
  studio.example.com \
  smtp.ionos.fr \
  465 \
  user@example.com \
  'your-password' \
  'Your App Name'
```

### 3. Configure Reverse Proxy

The script will output the port mappings. Configure your reverse proxy:

**Example Plesk Configuration:**
- API Domain (`api.example.com`): Proxy to `http://localhost:8000`
- Studio Domain (`studio.example.com`): Proxy to `http://localhost:8300`

**Example Nginx Configuration:**
```nginx
# API Domain
server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Studio Domain
server {
    listen 443 ssl http2;
    server_name studio.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:8300;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## Deployment Script Usage

### Command Syntax

```bash
./script.sh <project_slug> <api_domain> <studio_domain> [smtp_host] [smtp_port] [smtp_user] [smtp_pass] [smtp_sender_name]
```

### Parameters

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `project_slug` | ✅ Yes | Unique project identifier (alphanumeric, `-`, `_`) | `myproject` |
| `api_domain` | ✅ Yes | Domain for Supabase API | `api.example.com` |
| `studio_domain` | ✅ Yes | Domain for Supabase Studio | `studio.example.com` |
| `smtp_host` | ⚪ Optional | SMTP server hostname | `smtp.ionos.fr` |
| `smtp_port` | ⚪ Optional | SMTP server port (default: 587) | `465` |
| `smtp_user` | ⚪ Optional | SMTP username/email | `user@example.com` |
| `smtp_pass` | ⚪ Optional | SMTP password | `'P@ssw0rd!'` |
| `smtp_sender_name` | ⚪ Optional | Email sender name (default: Supabase) | `'My App'` |

**Note:** SMTP parameters must all be provided together or none at all.

### Examples

**1. Basic deployment (local development):**
```bash
./script.sh devproject localhost localhost
```

**2. Production with custom domains:**
```bash
./script.sh production \
  sbapi.myapp.com \
  studio.myapp.com
```

**3. Full production with SMTP (IONOS):**
```bash
./script.sh production \
  sbapi.myapp.com \
  studio.myapp.com \
  smtp.ionos.fr \
  465 \
  noreply@myapp.com \
  'MySecurePassword123!' \
  'MyApp'
```

**4. Full production with SMTP (Gmail):**
```bash
./script.sh production \
  sbapi.myapp.com \
  studio.myapp.com \
  smtp.gmail.com \
  587 \
  youremail@gmail.com \
  'your-app-password' \
  'MyApp'
```

### Deployment Output

After successful deployment, you'll see:

```
✅ Supabase project 'myproject' deployed successfully!

🔑 Credentials:
  - Service Role Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
  - Anon Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
  - PostgreSQL Password: rHpZBi60NETQNEeI...

🌐 Access URLs:
  - API: https://api.example.com
  - Studio: https://studio.example.com

🔌 Port Mappings (for reverse proxy):
  - Kong (API): 127.0.0.1:8000 → https://api.example.com
  - Studio: 127.0.0.1:8300 → https://studio.example.com
  - PostgreSQL: 127.0.0.1:8432 (internal)
  - Pooler: 127.0.0.1:8543 (internal)

📁 Project Directory: /opt/supabase/projects/myproject
📝 Configuration: /opt/supabase/projects/myproject/supabase/docker/.env
```

**⚠️ Important:** Save the Service Role Key and Anon Key - you'll need them for your application!

## Email Templates

The repository includes professionally branded HTML email templates for authentication flows.

### Available Templates

Located in `email-templates/`:

1. **`confirmation.html`** - Email verification for new sign-ups
2. **`recovery.html`** - Password reset requests
3. **`magic_link.html`** - Passwordless sign-in
4. **`invite.html`** - User invitations
5. **`email_change.html`** - Email address change confirmation

### Template Features

- ✅ Responsive design (mobile & desktop)
- ✅ Professional branding with logo support
- ✅ Gradient buttons with hover effects
- ✅ Email client compatible (Gmail, Outlook, Apple Mail)
- ✅ Template variables (Go template syntax)

### Customizing Templates

**1. Update Logo:**

Edit the logo URL in each template:

```html
<img src="YOUR_LOGO_URL_HERE" alt="Logo" style="width: 120px; height: auto;">
```

**2. Update Colors:**

Modify the gradient in the button CSS:

```html
<style>
  .cta-button {
    background: linear-gradient(135deg, #YOUR_COLOR_1 0%, #YOUR_COLOR_2 100%);
  }
</style>
```

**3. Customize Content:**

Edit the welcome message, footer text, or any static content in the HTML.

### Deploying Custom Templates

**Option 1: GitHub Raw URLs (Recommended)**

1. Fork this repository or create your own
2. Customize templates in `email-templates/`
3. Commit and push to GitHub
4. Get raw URLs: `https://raw.githubusercontent.com/USERNAME/REPO/main/email-templates/confirmation.html`
5. Update `.env` in your project:

```bash
cd /opt/supabase/projects/myproject/supabase/docker

# Edit .env file
sudo nano .env

# Add/update these variables:
GOTRUE_MAILER_TEMPLATES_CONFIRMATION=https://raw.githubusercontent.com/USERNAME/REPO/main/email-templates/confirmation.html
GOTRUE_MAILER_TEMPLATES_RECOVERY=https://raw.githubusercontent.com/USERNAME/REPO/main/email-templates/recovery.html
GOTRUE_MAILER_TEMPLATES_MAGIC_LINK=https://raw.githubusercontent.com/USERNAME/REPO/main/email-templates/magic_link.html
GOTRUE_MAILER_TEMPLATES_INVITE=https://raw.githubusercontent.com/USERNAME/REPO/main/email-templates/invite.html
GOTRUE_MAILER_TEMPLATES_EMAIL_CHANGE=https://raw.githubusercontent.com/USERNAME/REPO/main/email-templates/email_change.html
```

6. Recreate the auth container:

```bash
cd /opt/supabase/projects/myproject/supabase/docker
docker compose up -d --force-recreate --no-deps auth
```

**Option 2: Cloudinary/CDN**

1. Upload templates to Cloudinary or any CDN
2. Use the public URLs in `.env` configuration
3. Add cache-busting with timestamps: `?v=1234567890`

**Option 3: Local Files**

1. Copy templates to server:
```bash
sudo mkdir -p /opt/supabase/projects/myproject/email-templates
sudo cp email-templates/*.html /opt/supabase/projects/myproject/email-templates/
```

2. Update `docker-compose.override.yml`:
```yaml
services:
  auth:
    volumes:
      - /opt/supabase/projects/myproject/email-templates:/etc/gotrue/templates:ro
```

3. Update `.env`:
```bash
GOTRUE_MAILER_TEMPLATES_CONFIRMATION=/etc/gotrue/templates/confirmation.html
GOTRUE_MAILER_TEMPLATES_RECOVERY=/etc/gotrue/templates/recovery.html
# ... etc
```

### Template Variables

GoTrue automatically replaces these variables in your templates:

| Variable | Description | Example |
|----------|-------------|---------|
| `{{ .ConfirmationURL }}` | Email verification/action URL | Click to confirm |
| `{{ .Email }}` | User's email address | user@example.com |
| `{{ .Token }}` | Auth token (if needed) | abc123... |
| `{{ .TokenHash }}` | Hashed token | hash... |
| `{{ .SiteURL }}` | Your app's URL | https://app.com |

**Example usage in template:**
```html
<a href="{{ .ConfirmationURL }}" class="cta-button">
  Confirm Your Email
</a>
<p>Sent to: {{ .Email }}</p>
```

### Testing Email Templates

**1. Send test email:**

```bash
# Via psql
docker exec -it sb-myproject-db-1 psql -U postgres -d postgres -c \
  "SELECT auth.create_user('test@example.com', 'password123')"
```

**2. Check email delivery:**

```bash
# View GoTrue logs
docker logs sb-myproject-auth-1 --tail 50
```

**3. Common issues:**

- **Button text not visible**: Ensure `!important` is used for colors
- **Images not loading**: Check logo URL is publicly accessible
- **Template not updating**: Clear cache with `?v=TIMESTAMP` parameter
- **Email not sending**: Verify SMTP credentials in `.env`

## MCP Server Setup

MCP (Model Context Protocol) allows AI assistants like Claude to directly interact with your Supabase database.

### What is MCP?

MCP enables natural language database operations through AI assistants:
- Query tables without writing SQL
- Insert/update records through conversation
- Generate database reports
- Debug and analyze data

### Prerequisites

- Self-hosted Supabase instance deployed
- Service role key (from deployment output)
- Node.js installed locally (for npx)
- IDE with MCP support (Claude Code, Cursor, Windsurf, Zed)

### Configuration

#### For Claude Code

Add to your `~/.claude.json`:

```json
{
  "projects": {
    "/your/project/path": {
      "mcpServers": {
        "supabase": {
          "command": "npx",
          "args": [
            "-y",
            "@supabase/mcp-server-postgrest",
            "--apiUrl",
            "https://api.example.com/rest/v1",
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

#### For Cursor

Add to Cursor settings (`.cursor/config.json`):

```json
{
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": [
        "-y",
        "@supabase/mcp-server-postgrest",
        "--apiUrl",
        "https://api.example.com/rest/v1",
        "--apiKey",
        "YOUR_SERVICE_ROLE_KEY",
        "--schema",
        "public"
      ]
    }
  }
}
```

#### For Windsurf

Add to Windsurf MCP configuration:

```json
{
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": [
        "-y",
        "@supabase/mcp-server-postgrest",
        "--apiUrl",
        "https://api.example.com/rest/v1",
        "--apiKey",
        "YOUR_SERVICE_ROLE_KEY",
        "--schema",
        "public"
      ]
    }
  }
}
```

#### For Zed Editor

Add to Zed settings (`~/.config/zed/settings.json`):

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
          "https://api.example.com/rest/v1",
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

### Getting Your Service Role Key

```bash
# Navigate to project directory
cd /opt/supabase/projects/YOUR_PROJECT/supabase/docker

# Display service role key
grep SERVICE_ROLE_KEY .env
```

### Activation

1. **Save configuration** to appropriate config file
2. **Restart IDE completely** (quit and reopen)
3. **Verify connection**:
   - Claude Code: Type `/mcp`
   - Cursor: Check MCP panel
   - Windsurf: Check context servers
4. **Test**: Ask "List all tables in my database"

### Available MCP Tools

- **`postgrestRequest`** - Direct REST API requests
- **`sqlToRest`** - Convert SQL to PostgREST requests

### Example Queries

Once MCP is configured:

```
"Show me all users created today"
"Count active widget configurations"
"Update user email where id = '123'"
"Get the schema for the products table"
"Delete sessions older than 30 days"
```

### Troubleshooting MCP

**Connection Failed:**

1. Check logs:
```bash
# Claude Code logs
ls ~/Library/Caches/claude-cli-nodejs/-Users-USERNAME-PROJECT/mcp-logs-supabase/

# View latest log
tail -f ~/Library/Caches/claude-cli-nodejs/-Users-USERNAME-PROJECT/mcp-logs-supabase/*.txt
```

2. Test API manually:
```bash
curl -H "apikey: YOUR_SERVICE_ROLE_KEY" \
     -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
     https://api.example.com/rest/v1/
```

3. Common issues:
   - **"Please provide a base URL"**: Check `--apiUrl` syntax
   - **HTTP 401**: Verify service role key
   - **npx not found**: Install Node.js
   - **Config not loading**: Restart IDE completely

## Project Structure

```
supabase-selfhost-script/
├── script.sh                    # Main deployment script
├── README.md                    # This file
├── email-templates/             # Branded email templates
│   ├── confirmation.html        # Email verification
│   ├── recovery.html           # Password reset
│   ├── magic_link.html         # Passwordless login
│   ├── invite.html             # User invitations
│   └── email_change.html       # Email change confirmation
└── .gitignore

# After deployment, on server:
/opt/supabase/projects/
└── YOUR_PROJECT/
    └── supabase/
        └── docker/
            ├── .env                        # Configuration
            ├── docker-compose.yml          # Base compose file
            ├── docker-compose.override.yml # Custom overrides
            └── volumes/                    # Persistent data
                ├── db/                     # PostgreSQL data
                ├── storage/                # File storage
                └── logs/                   # Service logs
```

## Troubleshooting

### Storage Service Crashes

**Symptom:** "Failed to fetch buckets" or storage not loading

**Cause:** Password with special characters (like `/`) breaks URL parsing

**Solution:** The script automatically URL-encodes passwords. If you manually edit `.env`:

```bash
# Use Python to encode password
python3 -c "import urllib.parse; print(urllib.parse.quote('pass/word', safe=''))"
# Output: pass%2Fword

# Update STORAGE_DATABASE_URL in .env:
STORAGE_DATABASE_URL=postgresql://postgres:pass%2Fword@db:5432/postgres
```

### Authentication Redirects

**Symptom:** Email links redirect to API domain instead of frontend

**Solution:** Update `GOTRUE_SITE_URL` and `GOTRUE_URI_ALLOW_LIST` in `.env`:

```bash
cd /opt/supabase/projects/YOUR_PROJECT/supabase/docker

# Edit .env
GOTRUE_SITE_URL=https://your-frontend-app.com
GOTRUE_URI_ALLOW_LIST=https://*.yourapp.com/**,https://*.vercel.app/**,http://localhost:**

# Recreate auth container
docker compose up -d --force-recreate --no-deps auth
```

### Email Templates Not Updating

**Symptom:** Changes to templates not reflected in emails

**Cause:** GoTrue caches templates

**Solution:** Add cache-busting parameter to template URLs:

```bash
# In .env, append timestamp to URL:
GOTRUE_MAILER_TEMPLATES_CONFIRMATION=https://raw.githubusercontent.com/.../confirmation.html?v=1234567890

# Update timestamp after each change
# Recreate auth container
docker compose up -d --force-recreate --no-deps auth
```

**Important:** `docker compose restart` doesn't pick up env changes - always use `--force-recreate`.

### Port Conflicts

**Symptom:** "Port already in use" or containers fail to start

**Solution:** The script auto-detects free ports. To check manually:

```bash
# List all project ports
grep -r "127.0.0.1:" /opt/supabase/projects/*/supabase/docker/docker-compose.override.yml

# Check if port is in use
sudo lsof -i :8000
```

### Container Management

```bash
# Navigate to project
cd /opt/supabase/projects/YOUR_PROJECT/supabase/docker

# View running containers
docker compose ps

# View logs
docker compose logs -f auth          # Auth service
docker compose logs -f storage       # Storage service
docker compose logs -f kong          # API gateway

# Restart specific service
docker compose restart auth

# Recreate service (picks up env changes)
docker compose up -d --force-recreate --no-deps auth

# Stop all services
docker compose down

# Start all services
docker compose up -d

# Remove everything (including volumes)
docker compose down -v
```

### Database Access

```bash
# Connect to PostgreSQL
docker exec -it sb-YOUR_PROJECT-db-1 psql -U postgres -d postgres

# Import SQL dump
docker exec -i sb-YOUR_PROJECT-db-1 psql -U postgres -d postgres < dump.sql

# Export database
docker exec sb-YOUR_PROJECT-db-1 pg_dump -U postgres -d postgres > backup.sql

# View database size
docker exec sb-YOUR_PROJECT-db-1 psql -U postgres -c "SELECT pg_size_pretty(pg_database_size('postgres'))"
```

### Viewing Service Logs

```bash
cd /opt/supabase/projects/YOUR_PROJECT/supabase/docker

# Real-time logs (all services)
docker compose logs -f

# Specific service
docker compose logs -f auth
docker compose logs -f storage
docker compose logs -f kong

# Last 100 lines
docker compose logs --tail 100 auth

# Since specific time
docker compose logs --since 30m auth
```

## Security

### Best Practices

1. **🔐 Protect Service Role Key**
   - Never commit to git
   - Never expose in client-side code
   - Use only in trusted server environments
   - Rotate periodically

2. **🔒 Use Row Level Security (RLS)**
   - Enable RLS on all tables
   - Service role bypasses RLS - use with caution
   - Use anon key in client applications

3. **🌐 Restrict Access**
   - Configure firewall rules
   - Use `GOTRUE_URI_ALLOW_LIST` for OAuth redirects
   - Limit API access by IP if possible

4. **📧 SMTP Security**
   - Use app-specific passwords (Gmail)
   - Enable TLS/SSL (port 465 or STARTTLS on 587)
   - Don't commit SMTP credentials

5. **🔄 Regular Updates**
   - Monitor Supabase releases
   - Update Docker images periodically
   - Backup before updates

### Backup Strategy

```bash
# Backup script (save as /root/backup-supabase.sh)
#!/bin/bash
PROJECT="YOUR_PROJECT"
BACKUP_DIR="/opt/supabase/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# Database backup
docker exec sb-${PROJECT}-db-1 pg_dump -U postgres -d postgres | \
  gzip > "$BACKUP_DIR/${PROJECT}_db_${DATE}.sql.gz"

# Configuration backup
cp -r /opt/supabase/projects/${PROJECT}/supabase/docker/.env \
  "$BACKUP_DIR/${PROJECT}_env_${DATE}"

# Keep only last 7 days
find "$BACKUP_DIR" -name "${PROJECT}_*" -mtime +7 -delete

echo "✅ Backup completed: $BACKUP_DIR/${PROJECT}_db_${DATE}.sql.gz"
```

Add to crontab for daily backups:
```bash
# Edit crontab
sudo crontab -e

# Add line (daily at 2 AM):
0 2 * * * /root/backup-supabase.sh
```

### Environment Variables Reference

Key `.env` variables you may need to customize:

```bash
# API URLs
API_EXTERNAL_URL=https://api.example.com
STUDIO_URL=https://studio.example.com
GOTRUE_SITE_URL=https://your-frontend.com

# Security Keys (auto-generated by script)
SERVICE_ROLE_KEY=eyJhbGci...
ANON_KEY=eyJhbGci...
JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters-long
POSTGRES_PASSWORD=your-postgres-password

# SMTP Configuration
GOTRUE_SMTP_HOST=smtp.ionos.fr
GOTRUE_SMTP_PORT=465
GOTRUE_SMTP_USER=user@example.com
GOTRUE_SMTP_PASS=your-password
GOTRUE_SMTP_ADMIN_EMAIL=admin@example.com
GOTRUE_SMTP_SENDER_NAME=Your App Name

# OAuth Redirects
GOTRUE_URI_ALLOW_LIST=https://*.example.com/**,http://localhost:**

# Email Templates
GOTRUE_MAILER_TEMPLATES_CONFIRMATION=https://raw.githubusercontent.com/.../confirmation.html
GOTRUE_MAILER_TEMPLATES_RECOVERY=https://raw.githubusercontent.com/.../recovery.html
GOTRUE_MAILER_TEMPLATES_MAGIC_LINK=https://raw.githubusercontent.com/.../magic_link.html
GOTRUE_MAILER_TEMPLATES_INVITE=https://raw.githubusercontent.com/.../invite.html
GOTRUE_MAILER_TEMPLATES_EMAIL_CHANGE=https://raw.githubusercontent.com/.../email_change.html
```

## Resources

### Documentation

- [Supabase Official Docs](https://supabase.com/docs)
- [Supabase Self-Hosting Guide](https://supabase.com/docs/guides/self-hosting)
- [PostgREST Documentation](https://postgrest.org/)
- [GoTrue (Auth) Documentation](https://github.com/supabase/gotrue)
- [MCP Specification](https://modelcontextprotocol.io/)

### Community

- [Supabase GitHub](https://github.com/supabase/supabase)
- [Supabase Discord](https://discord.supabase.com/)
- [Supabase Community](https://github.com/supabase-community)

### Tools

- [Supabase CLI](https://supabase.com/docs/guides/cli)
- [Supabase MCP Server](https://www.npmjs.com/package/@supabase/mcp-server-postgrest)
- [Docker Documentation](https://docs.docker.com/)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request

## License

MIT License - see repository for details

## Support

For issues:
- **Script issues**: Open a GitHub issue
- **Supabase issues**: Check [Supabase Discord](https://discord.supabase.com/)
- **Self-hosting**: See [official self-hosting docs](https://supabase.com/docs/guides/self-hosting)

---

**Last Updated**: October 2025
**Script Version**: 1.0
**Supabase Version**: Latest (pulled from official repository)
**MCP Server**: `@supabase/mcp-server-postgrest@latest`
**Tested On**: Ubuntu 22.04, Docker 24.0+
