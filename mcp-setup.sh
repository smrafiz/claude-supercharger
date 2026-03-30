#!/usr/bin/env bash
set -euo pipefail

# Claude Supercharger v1.0.0 - MCP Server Setup
# Installs recommended MCP servers for Claude Code

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Claude Supercharger MCP Server Setup   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}"
echo ""

CONFIG_FILE=~/.claude/claude_desktop_config.json
BACKUP_FILE=~/.claude/claude_desktop_config.backup.$(date +%Y%m%d-%H%M%S).json

# Check if Claude Desktop config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}⚠️  Claude Desktop config not found at $CONFIG_FILE${NC}"
    echo -e "${BLUE}Creating new configuration...${NC}"
    mkdir -p ~/.claude
    echo '{"mcpServers": {}}' > "$CONFIG_FILE"
else
    echo -e "${GREEN}✓ Found existing Claude Desktop config${NC}"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo -e "${BLUE}📦 Backup created: $BACKUP_FILE${NC}"
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}  Recommended MCP Server Stack (2026)     ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""

echo -e "${GREEN}Tier 1 - Must-Have (Core Enhancement)${NC}"
echo "  • Context7         - Documentation lookup (API key required)"
echo "  • Sequential       - Complex problem solving"
echo "  • Memory           - Persistent knowledge graphs"
echo ""

echo -e "${BLUE}Tier 2 - Highly Useful (Productivity)${NC}"
echo "  • GitHub           - Repository operations (token required)"
echo "  • Brave Search     - Current information (API key required)"
echo "  • Filesystem       - Secure file operations"
echo ""

echo -e "${YELLOW}Tier 3 - Specialized (Advanced)${NC}"
echo "  • Playwright       - Browser automation"
echo "  • Puppeteer        - Chrome automation"
echo "  • Prisma           - Database operations"
echo "  • Neon             - Serverless Postgres (API key required)"
echo "  • Magic UI         - React component library"
echo "  • Slack            - Team communication (token required)"
echo ""

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""

echo -e "${BLUE}Which tier would you like to install?${NC}"
echo "  1) Tier 1 only (3 servers, 1 API key needed)"
echo "  2) Tier 1 + 2 (6 servers, 3 API keys needed)"
echo "  3) All tiers (12 servers, 5 API keys needed)"
echo "  4) Custom selection"
echo "  5) Exit"
echo ""
read -p "Choose option [1-5]: " tier_choice

case $tier_choice in
    1)
        INSTALL_SERVERS=("context7" "sequential-thinking" "memory")
        ;;
    2)
        INSTALL_SERVERS=("context7" "sequential-thinking" "memory" "github" "brave-search" "filesystem")
        ;;
    3)
        INSTALL_SERVERS=("context7" "sequential-thinking" "memory" "github" "brave-search" "filesystem" "playwright" "puppeteer" "prisma" "neon" "magic-ui" "slack")
        ;;
    4)
        echo ""
        echo -e "${BLUE}Custom selection (enter y/n for each):${NC}"
        INSTALL_SERVERS=()

        servers=("context7" "sequential-thinking" "memory" "github" "brave-search" "filesystem" "playwright" "puppeteer" "prisma" "neon" "magic-ui" "slack")
        labels=("Context7 (API)" "Sequential Thinking" "Memory" "GitHub (token)" "Brave Search (API)" "Filesystem" "Playwright" "Puppeteer" "Prisma" "Neon (API)" "Magic UI" "Slack (token)")

        for i in "${!servers[@]}"; do
            read -p "  ${labels[$i]}? [y/N]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                INSTALL_SERVERS+=("${servers[$i]}")
            fi
        done
        ;;
    5)
        echo -e "${YELLOW}Setup cancelled.${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice.${NC}"
        exit 1
        ;;
esac

if [ ${#INSTALL_SERVERS[@]} -eq 0 ]; then
    echo -e "${YELLOW}No servers selected. Exiting.${NC}"
    exit 0
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installing ${#INSTALL_SERVERS[@]} MCP Server(s)${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""

# Function to add server to config
add_server() {
    local server_name=$1
    local server_config=$2

    # Check if server already exists
    if grep -q "\"$server_name\"" "$CONFIG_FILE" 2>/dev/null; then
        echo -e "${YELLOW}  ⚠️  $server_name already configured, skipping${NC}"
        return
    fi

    # Use Python to safely merge JSON (fallback to manual if not available)
    if command -v python3 &> /dev/null; then
        python3 << EOF
import json
with open("$CONFIG_FILE", "r") as f:
    config = json.load(f)
if "mcpServers" not in config:
    config["mcpServers"] = {}
config["mcpServers"]["$server_name"] = $server_config
with open("$CONFIG_FILE", "w") as f:
    json.dump(config, f, indent=2)
EOF
        echo -e "${GREEN}  ✓ $server_name configured${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Python not found. Manual configuration required for $server_name${NC}"
        echo -e "${YELLOW}     See docs/MCP_SETUP.md for instructions${NC}"
    fi
}

# Install selected servers
for server in "${INSTALL_SERVERS[@]}"; do
    case $server in
        "context7")
            echo -e "${BLUE}📥 Installing Context7...${NC}"
            echo -e "${YELLOW}   API Key required from: https://context.ai${NC}"
            read -p "   Enter Context7 API key (or press Enter to skip): " context7_key

            if [ -n "$context7_key" ]; then
                add_server "context7" "{
  \"command\": \"npx\",
  \"args\": [\"-y\", \"@upstash/context7-mcp\"],
  \"env\": {
    \"CONTEXT7_API_KEY\": \"$context7_key\"
  }
}"
            else
                echo -e "${YELLOW}   ⚠️  Skipped. Add API key later in $CONFIG_FILE${NC}"
            fi
            ;;

        "sequential-thinking")
            echo -e "${BLUE}📥 Installing Sequential Thinking...${NC}"
            add_server "sequential-thinking" "{
  \"command\": \"npx\",
  \"args\": [\"-y\", \"@modelcontextprotocol/server-sequential-thinking\"]
}"
            ;;

        "memory")
            echo -e "${BLUE}📥 Installing Memory...${NC}"
            add_server "memory" "{
  \"command\": \"npx\",
  \"args\": [\"-y\", \"@modelcontextprotocol/server-memory\"]
}"
            ;;

        "github")
            echo -e "${BLUE}📥 Installing GitHub...${NC}"
            echo -e "${YELLOW}   GitHub token required from: https://github.com/settings/tokens${NC}"
            read -p "   Enter GitHub Personal Access Token (or press Enter to skip): " github_token

            if [ -n "$github_token" ]; then
                add_server "github" "{
  \"command\": \"npx\",
  \"args\": [\"-y\", \"@modelcontextprotocol/server-github\"],
  \"env\": {
    \"GITHUB_PERSONAL_ACCESS_TOKEN\": \"$github_token\"
  }
}"
            else
                echo -e "${YELLOW}   ⚠️  Skipped. Add token later in $CONFIG_FILE${NC}"
            fi
            ;;

        "brave-search")
            echo -e "${BLUE}📥 Installing Brave Search...${NC}"
            echo -e "${YELLOW}   API Key required from: https://brave.com/search/api/${NC}"
            read -p "   Enter Brave Search API key (or press Enter to skip): " brave_key

            if [ -n "$brave_key" ]; then
                add_server "brave-search" "{
  \"command\": \"npx\",
  \"args\": [\"-y\", \"@modelcontextprotocol/server-brave-search\"],
  \"env\": {
    \"BRAVE_API_KEY\": \"$brave_key\"
  }
}"
            else
                echo -e "${YELLOW}   ⚠️  Skipped. Add API key later in $CONFIG_FILE${NC}"
            fi
            ;;

        "filesystem")
            echo -e "${BLUE}📥 Installing Filesystem...${NC}"
            echo -e "${YELLOW}   Default allowed directory: $HOME${NC}"
            read -p "   Custom directory (or press Enter for default): " fs_dir
            fs_dir=${fs_dir:-$HOME}

            add_server "filesystem" "{
  \"command\": \"npx\",
  \"args\": [\"-y\", \"@modelcontextprotocol/server-filesystem\", \"$fs_dir\"]
}"
            ;;

        "playwright")
            echo -e "${BLUE}📥 Installing Playwright...${NC}"
            add_server "playwright" "{
  \"command\": \"npx\",
  \"args\": [\"-y\", \"@executeautomation/playwright-mcp-server\"]
}"
            ;;

        "puppeteer")
            echo -e "${BLUE}📥 Installing Puppeteer...${NC}"
            add_server "puppeteer" "{
  \"command\": \"npx\",
  \"args\": [\"-y\", \"@modelcontextprotocol/server-puppeteer\"]
}"
            ;;

        "prisma")
            echo -e "${BLUE}📥 Installing Prisma...${NC}"
            echo -e "${YELLOW}   Note: Requires Prisma CLI in your project${NC}"
            add_server "prisma" "{
  \"command\": \"npx\",
  \"args\": [\"prisma\", \"mcp\"]
}"
            ;;

        "neon")
            echo -e "${BLUE}📥 Installing Neon...${NC}"
            echo -e "${YELLOW}   Connection string required from: https://neon.tech${NC}"
            read -p "   Enter Neon connection string (or press Enter to skip): " neon_conn

            if [ -n "$neon_conn" ]; then
                add_server "neon" "{
  \"command\": \"npx\",
  \"args\": [\"-y\", \"@neondatabase/mcp-server-neon\"],
  \"env\": {
    \"DATABASE_URL\": \"$neon_conn\"
  }
}"
            else
                echo -e "${YELLOW}   ⚠️  Skipped. Add connection string later in $CONFIG_FILE${NC}"
            fi
            ;;

        "magic-ui")
            echo -e "${BLUE}📥 Installing Magic UI...${NC}"
            add_server "magic-ui" "{
  \"command\": \"npx\",
  \"args\": [\"-y\", \"@magicuidesign/mcp-server-magicui\"]
}"
            ;;

        "slack")
            echo -e "${BLUE}📥 Installing Slack...${NC}"
            echo -e "${YELLOW}   Bot token required from: https://api.slack.com/apps${NC}"
            read -p "   Enter Slack Bot Token (or press Enter to skip): " slack_token

            if [ -n "$slack_token" ]; then
                add_server "slack" "{
  \"command\": \"npx\",
  \"args\": [\"-y\", \"@modelcontextprotocol/server-slack\"],
  \"env\": {
    \"SLACK_BOT_TOKEN\": \"$slack_token\"
  }
}"
            else
                echo -e "${YELLOW}   ⚠️  Skipped. Add token later in $CONFIG_FILE${NC}"
            fi
            ;;
    esac
done

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✓ MCP Setup Complete!                ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╗${NC}"
echo ""

echo -e "${BLUE}📋 Summary:${NC}"
echo "  • Installed: ${#INSTALL_SERVERS[@]} MCP server(s)"
echo "  • Config: $CONFIG_FILE"
echo "  • Backup: $BACKUP_FILE"
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Restart Claude Desktop (quit completely and reopen)"
echo "  2. Verify servers: Claude should show MCP icons in chat"
echo "  3. Missing API keys? Edit: $CONFIG_FILE"
echo "  4. Full guide: docs/MCP_SETUP.md"
echo ""

echo -e "${CYAN}Testing servers (optional):${NC}"
read -p "Test MCP servers now? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}🔍 Validating configuration...${NC}"

    if command -v python3 &> /dev/null; then
        python3 << 'EOF'
import json
try:
    with open("~/.claude/claude_desktop_config.json".replace("~", __import__("os").path.expanduser("~")), "r") as f:
        config = json.load(f)
    if "mcpServers" in config and len(config["mcpServers"]) > 0:
        print("\033[0;32m✓ Configuration valid\033[0m")
        print(f"\033[0;34mConfigured servers: {', '.join(config['mcpServers'].keys())}\033[0m")
    else:
        print("\033[1;33m⚠️  No servers configured\033[0m")
except Exception as e:
    print(f"\033[0;31m✗ Configuration error: {e}\033[0m")
EOF
    else
        echo -e "${YELLOW}Python not available for validation${NC}"
    fi

    echo ""
    echo -e "${BLUE}To test servers:${NC}"
    echo "  1. Restart Claude Desktop"
    echo "  2. Try: 'Search documentation for React hooks' (Context7)"
    echo "  3. Try: 'Analyze this complex problem step by step' (Sequential)"
    echo "  4. Try: 'Remember: I prefer TypeScript strict mode' (Memory)"
fi

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
