#!/bin/bash
# <xbar.title>Claude Terminal Navigator</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>Claude Terminal Navigator</xbar.author>
# <xbar.author.github>GailenTech</xbar.author.github>
# <xbar.desc>Monitor and navigate Claude CLI sessions from the menu bar</xbar.desc>
# <xbar.dependencies>bash</xbar.dependencies>

# Configuration
CLAUDE_SESSIONS_DIR="${CLAUDE_NAV_DIR:-$HOME/.claude}/sessions"
SCRIPT_DIR="/Volumes/DevelopmentProjects/Claude/claude-terminal-navigator/bin"
CLAUDE_JUMP="$SCRIPT_DIR/claude-jump"
CLAUDE_CLEANUP="$SCRIPT_DIR/claude-cleanup"

# Colors
COLOR_ACTIVE="green"
COLOR_WAITING="orange"
COLOR_INACTIVE="gray"

# Helper functions
get_cpu_usage() {
    local pid=$1
    ps -p "$pid" -o %cpu= 2>/dev/null | xargs || echo "0.0"
}

get_memory_usage() {
    local pid=$1
    # Get RSS in KB and convert to MB
    local rss_kb=$(ps -p "$pid" -o rss= 2>/dev/null | xargs || echo "0")
    echo "scale=1; $rss_kb / 1024" | bc 2>/dev/null || echo "0"
}

is_session_active() {
    local pid=$1
    # Check if Claude is actively processing (CPU > 5%)
    local cpu=$(get_cpu_usage "$pid")
    (( $(echo "$cpu > 5" | bc -l 2>/dev/null || echo 0) ))
}

format_duration() {
    local start_time=$1
    local now=$(date +%s)
    
    # Parse ISO 8601 date
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS date command
        local start=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_time" +%s 2>/dev/null || echo $now)
    else
        # GNU date command
        local start=$(date -d "$start_time" +%s 2>/dev/null || echo $now)
    fi
    
    local duration=$((now - start))
    
    if [ $duration -lt 60 ]; then
        echo "${duration}s"
    elif [ $duration -lt 3600 ]; then
        echo "$((duration / 60))m"
    else
        echo "$((duration / 3600))h $((duration % 3600 / 60))m"
    fi
}

# Count active and waiting sessions
active_count=0
waiting_count=0
total_cpu=0

# Arrays to store session data
declare -a sessions_data

# First pass: collect session data
for session_file in "$CLAUDE_SESSIONS_DIR"/*.json; do
    [ -e "$session_file" ] || continue
    
    # Parse JSON manually (pure bash)
    content=$(cat "$session_file")
    pid=$(echo "$content" | grep -o '"pid": "[^"]*"' | cut -d'"' -f4)
    
    # Check if process is alive
    if kill -0 "$pid" 2>/dev/null; then
        dir_name=$(echo "$content" | grep -o '"dir_name": "[^"]*"' | cut -d'"' -f4)
        terminal=$(echo "$content" | grep -o '"terminal": "[^"]*"' | cut -d'"' -f4)
        start_time=$(echo "$content" | grep -o '"start_time": "[^"]*"' | cut -d'"' -f4)
        working_dir=$(echo "$content" | grep -o '"working_dir": "[^"]*"' | cut -d'"' -f4)
        
        cpu=$(get_cpu_usage "$pid")
        mem=$(get_memory_usage "$pid")
        duration=$(format_duration "$start_time")
        
        if is_session_active "$pid"; then
            ((active_count++))
            status="active"
        else
            ((waiting_count++))
            status="waiting"
        fi
        
        # Add to total CPU
        total_cpu=$(echo "$total_cpu + $cpu" | bc 2>/dev/null || echo $total_cpu)
        
        # Store session data
        sessions_data+=("$pid|$dir_name|$terminal|$cpu|$mem|$duration|$status|$working_dir")
    fi
done

# Menu bar display
if [ $active_count -gt 0 ]; then
    echo "Claude 🟢 $active_count | color=$COLOR_ACTIVE"
    echo "---"
    echo "Active Sessions: $active_count | color=$COLOR_ACTIVE"
elif [ $waiting_count -gt 0 ]; then
    echo "Claude 🟡 $waiting_count | color=$COLOR_WAITING"
    echo "---"
    echo "Waiting Sessions: $waiting_count | color=$COLOR_WAITING"
else
    echo "Claude ⚪ | color=$COLOR_INACTIVE"
    echo "---"
    echo "No Active Sessions | color=$COLOR_INACTIVE"
fi

if [ ${#sessions_data[@]} -gt 0 ]; then
    echo "Total CPU: ${total_cpu}% | color=$COLOR_INACTIVE"
fi

echo "---"

# Display sessions
if [ ${#sessions_data[@]} -gt 0 ]; then
    echo "Sessions"
    
    # Sort by status (active first) then by CPU usage
    IFS=$'\n' sorted_sessions=($(printf '%s\n' "${sessions_data[@]}" | sort -t'|' -k7,7 -k4,4nr))
    
    for session in "${sorted_sessions[@]}"; do
        IFS='|' read -r pid dir_name terminal cpu mem duration status working_dir <<< "$session"
        
        if [ "$status" = "active" ]; then
            status_icon="🟢"
            status_color=$COLOR_ACTIVE
        else
            status_icon="🟡"
            status_color=$COLOR_WAITING
        fi
        
        # Main session entry
        echo "--$status_icon $dir_name | color=$status_color bash='$CLAUDE_JUMP' param1=$pid terminal=false"
        
        # Session details submenu
        echo "----📊 CPU: ${cpu}% | color=$COLOR_INACTIVE"
        echo "----💾 Memory: ${mem} MB | color=$COLOR_INACTIVE"
        echo "----⏱️  Duration: $duration | color=$COLOR_INACTIVE"
        echo "----🖥️  Terminal: $terminal | color=$COLOR_INACTIVE"
        echo "----📁 Path: $working_dir | color=$COLOR_INACTIVE font=Monaco size=10"
        echo "------"
        echo "----🔍 Jump to Session | bash='$CLAUDE_JUMP' param1=$pid terminal=false"
        echo "----🚮 Kill Session | bash='/bin/kill' param1=$pid terminal=false color=red"
        echo "----📋 Copy Path | bash='echo' param1=\"$working_dir\" param2='|' param3='pbcopy' terminal=false"
    done
    
    echo "---"
fi

# Actions menu
echo "Actions"
echo "--🧹 Cleanup Dead Sessions | bash='$CLAUDE_CLEANUP' terminal=false"
echo "--🚀 Launch New Claude | bash='/opt/homebrew/bin/claude' terminal=true"
echo "--📂 Open Sessions Folder | bash='open' param1='$CLAUDE_SESSIONS_DIR' terminal=false"
echo "---"

# Settings menu
echo "Settings"
echo "--🔄 Refresh Now | refresh=true"
echo "--📝 Edit Monitor Script | bash='open' param1='-e' param2='$0' terminal=false"
echo "--📍 Plugin Location: $(dirname "$0") | color=$COLOR_INACTIVE font=Monaco size=10"
echo "---"

# Info
echo "About Claude Terminal Navigator"
echo "--Version: 1.0 | color=$COLOR_INACTIVE"
echo "--GitHub: GailenTech/claude-terminal-navigator | href='https://github.com/GailenTech/claude-terminal-navigator' color=$COLOR_INACTIVE"