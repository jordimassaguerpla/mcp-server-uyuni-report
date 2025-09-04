PS1=""
VERSION=$(gemini --version)
MODEL=gemini-2.5-flash
MCP_SERVER_UYUNI=mcp-server-uyuni-report
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# A function to display text with a "burst" typing animation.
# It pauses for a longer duration at a specified character interval.
#
# Usage: type_burst "Your text here" [pause_interval]
# The pause_interval is optional, defaults to 10.
type_burst() {
  local text="$1"
  local interval=${2:-120} # Use provided interval or default
  
  local char_delay=0.02
  local interval_pause=0.2

  for (( i=0; i<${#text}; i++ )); do
    printf "%s" "${text:$i:1}"
    
    if (( (i + 1) % interval == 0 )); then
      sleep "$interval_pause"
    else
      sleep "$char_delay"
    fi
  done
  echo
}

echo -e "${NC}"
echo "Using gemini-cli-$VERSION with model $MODEL and $MCP_SERVER_UYUNI"
sleep 1
type_burst "What can I do for you?"
echo -e "${GREEN}"
sleep 2
prompt="Analyze the Mean Patch Time on my Uyuni server to identify the biggest influencing factors.

Please investigate the following by trying different filter combinations with the available tools:
1.  **Time Frames:** Compare different periods (e.g., last quarter vs. last year).
2.  **Operating Systems:** Is there a significant difference in patch times between OS families?
3.  **Organizations:** Does belonging to a specific organization impact patch times?
4.  **Advisory Types & Severities:** Do security advisories have different patch times compared to bugfixes? Does severity play a role?

Summarize all in 900 characters maximum.

To support your analysis, please generate plots illustrating the key trends you discover.

Finally, provide a summary of your conclusions and give actionable advice on how to reduce the overall Mean Patch Time.
"
type_burst "$prompt"
echo -e "${NC}"
type_burst "Thinking ...."
echo -e "${NC}"
result=$(echo "$prompt" | gemini --model=$MODEL --allowed-mcp-server-names $MCP_SERVER_UYUNI --prompt -y 2> errors.txt)
clear
type_burst "$result"
sleep 4s
echo ""
type_burst "Displaying plots..."
sleep 2s
gwenview --fullscreen --slideshow plots 2>/dev/null
echo ""
type_burst "More information at http://github.com/uyuni-project/mcp-server-uyuni"
type_burst "Happy hacking!"
