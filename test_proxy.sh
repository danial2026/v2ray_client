#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Proxy configuration
SOCKS_PROXY="socks5://127.0.0.1:10808"
HTTP_PROXY="http://127.0.0.1:10809"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   V2Ray SOCKS Proxy Connection Test${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Test 1: Check if proxy is listening
echo -e "${YELLOW}[1/4] Checking if SOCKS proxy is listening on port 10808...${NC}"
if nc -z 127.0.0.1 10808 2>/dev/null; then
    echo -e "${GREEN}✓ SOCKS proxy is listening${NC}"
else
    echo -e "${RED}✗ SOCKS proxy is NOT listening on port 10808${NC}"
    echo -e "${RED}Please start V2Ray first!${NC}"
    exit 1
fi
echo ""

# Test 2: Ping test through proxy (HTTP request as ICMP won't work through SOCKS)
echo -e "${YELLOW}[2/4] Testing connectivity through proxy...${NC}"
if curl --socks5 "$SOCKS_PROXY" -s --connect-timeout 10 https://www.google.com/generate_204 -o /dev/null -w "%{http_code}" | grep -q "204\|200"; then
    echo -e "${GREEN}✓ Successfully connected through proxy${NC}"
else
    echo -e "${RED}✗ Failed to connect through proxy${NC}"
    exit 1
fi
echo ""

# Test 3: Get IP information
echo -e "${YELLOW}[3/4] Fetching IP information through proxy...${NC}"
IP_INFO=$(curl --socks5 "$SOCKS_PROXY" -s --connect-timeout 10 "https://ipapi.co/json/" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$IP_INFO" ]; then
    echo -e "${RED}✗ Failed to fetch IP information${NC}"
    exit 1
fi

# Parse JSON response
IP=$(echo "$IP_INFO" | grep -o '"ip":"[^"]*' | cut -d'"' -f4)
COUNTRY=$(echo "$IP_INFO" | grep -o '"country_name":"[^"]*' | cut -d'"' -f4)
COUNTRY_CODE=$(echo "$IP_INFO" | grep -o '"country_code":"[^"]*' | cut -d'"' -f4)
CITY=$(echo "$IP_INFO" | grep -o '"city":"[^"]*' | cut -d'"' -f4)
ISP=$(echo "$IP_INFO" | grep -o '"org":"[^"]*' | cut -d'"' -f4)
REGION=$(echo "$IP_INFO" | grep -o '"region":"[^"]*' | cut -d'"' -f4)

# Country flag emoji mapping (common countries)
declare -A FLAGS=(
    ["US"]="🇺🇸"
    ["GB"]="🇬🇧"
    ["DE"]="🇩🇪"
    ["FR"]="🇫🇷"
    ["JP"]="🇯🇵"
    ["CN"]="🇨🇳"
    ["IN"]="🇮🇳"
    ["CA"]="🇨🇦"
    ["AU"]="🇦🇺"
    ["NL"]="🇳🇱"
    ["SG"]="🇸🇬"
    ["IR"]="🇮🇷"
    ["RU"]="🇷🇺"
    ["BR"]="🇧🇷"
    ["IT"]="🇮🇹"
    ["ES"]="🇪🇸"
    ["KR"]="🇰🇷"
    ["SE"]="🇸🇪"
    ["CH"]="🇨🇭"
    ["NO"]="🇳🇴"
    ["FI"]="🇫🇮"
    ["PL"]="🇵🇱"
    ["TR"]="🇹🇷"
    ["UA"]="🇺🇦"
    ["AE"]="🇦🇪"
)

FLAG="${FLAGS[$COUNTRY_CODE]:-🌍}"

echo -e "${GREEN}✓ Successfully retrieved IP information${NC}"
echo ""

# Test 4: Display results
echo -e "${YELLOW}[4/4] Connection Details:${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "  ${GREEN}IP Address:${NC}  $IP"
echo -e "  ${GREEN}Country:${NC}     $FLAG  $COUNTRY"
echo -e "  ${GREEN}City:${NC}        $CITY, $REGION"
echo -e "  ${GREEN}ISP:${NC}         $ISP"
echo -e "${BLUE}========================================${NC}"
echo ""

# Bonus: Compare with direct connection
echo -e "${YELLOW}[BONUS] Your real IP (without proxy):${NC}"
REAL_IP=$(curl -s --connect-timeout 5 "https://api.ipify.org?format=text" 2>/dev/null)
if [ -n "$REAL_IP" ]; then
    if [ "$REAL_IP" != "$IP" ]; then
        echo -e "${GREEN}✓ Real IP: $REAL_IP (different from proxy IP)${NC}"
        echo -e "${GREEN}✓ Proxy is working correctly!${NC}"
    else
        echo -e "${RED}⚠ Real IP matches proxy IP - proxy might not be routing traffic!${NC}"
    fi
else
    echo -e "${YELLOW}Could not fetch real IP${NC}"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}        All tests passed! ✓${NC}"
echo -e "${GREEN}========================================${NC}"
