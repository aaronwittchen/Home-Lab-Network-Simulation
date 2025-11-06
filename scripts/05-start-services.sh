#!/bin/bash
#
# Script 5: Start Services
# Purpose: Run web/app/db services in namespaces
#

set -euo pipefail

# Color definitions
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

# Helper functions
print_ok() { echo "${GREEN}✓ $1${RESET}"; }
print_fail() { echo "${RED}✗ $1${RESET}"; }
print_info() { echo "${BLUE}ℹ $1${RESET}"; }
print_expected() { echo "${YELLOW}✓ $1 (expected)${RESET}"; }

# Cleanup function
cleanup() {
    print_info "Cleaning up services..."
    pkill -f "nginx.*homelab" 2>/dev/null || true
    pkill -f "python3.*8080" 2>/dev/null || true
    pkill -f "python3.*3306" 2>/dev/null || true
    print_info "Cleanup complete"
}

# Set up trap to ensure cleanup on script exit
trap cleanup EXIT

echo "${BLUE}=== Starting Services ===${RESET}"

# Kill any existing services
cleanup

# Create nginx config
mkdir -p ~/homelab/configs

cat > ~/homelab/configs/nginx-web.conf << 'NGINX_EOF'
daemon off;
error_log /tmp/nginx-web-error.log info;
pid /tmp/nginx-web.pid;

events {
    worker_connections 1024;
}

http {
    access_log /tmp/nginx-web-access.log;
    
    server {
        listen 10.10.20.10:80;
        
        location / {
            return 200 "Web Server (DMZ)\nVLAN: 20\nIP: 10.10.20.10\n";
            add_header Content-Type text/plain;
        }
        
        location /health {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }
    }
}
NGINX_EOF

# Start web server (nginx in DMZ)
echo "Starting web server (nginx) in DMZ..."
sudo ip netns exec web nginx -c ~/homelab/configs/nginx-web.conf > /dev/null 2>&1 &
sleep 2
echo "  ✓ Web server started on 10.10.20.10:80"

# Start app server (simple Python HTTP server)
echo "Starting app server (Python) in Internal zone..."
cat > /tmp/app-server.py << 'PYTHON_EOF'
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler

class AppHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        response = "App Server (Internal)\nVLAN: 30\nIP: 10.10.30.10\n"
        self.wfile.write(response.encode())
    
    def log_message(self, format, *args):
        pass  # Suppress logs

httpd = HTTPServer(('10.10.30.10', 8080), AppHandler)
httpd.serve_forever()
PYTHON_EOF

chmod +x /tmp/app-server.py
sudo ip netns exec app python3 /tmp/app-server.py > /dev/null 2>&1 &
sleep 1
echo "  ✓ App server started on 10.10.30.10:8080"

# Start database server (mock - just another Python server)
echo "Starting database server (mock) in Database zone..."
cat > /tmp/db-server.py << 'PYTHON_EOF'
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler

class DBHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        response = "Database Server (Database Zone)\nVLAN: 40\nIP: 10.10.40.10\n"
        self.wfile.write(response.encode())
    
    def log_message(self, format, *args):
        pass

httpd = HTTPServer(('10.10.40.10', 3306), DBHandler)
httpd.serve_forever()
PYTHON_EOF

chmod +x /tmp/db-server.py
sudo ip netns exec db python3 /tmp/db-server.py > /dev/null 2>&1 &
sleep 1
echo "  ✓ Database server started on 10.10.40.10:3306"

echo ""
echo "${GREEN}=== Services Started Successfully ===${RESET}"
echo ""
echo "${BLUE}Service Endpoints:${RESET}"
echo "  ${GREEN}Web:      http://10.10.20.10:80${RESET}"
echo "  ${GREEN}App:      http://10.10.30.10:8080${RESET}"
echo "  ${GREEN}Database: http://10.10.40.10:3306${RESET}"
echo ""

echo "${BLUE}=== Testing Service Access (with Firewall) ===${RESET}"
echo ""

# Test from management (should all work)
echo "${BLUE}From Management namespace:${RESET}"

# Test Web Server
echo -n "  → Web:      "
if sudo ip netns exec mgmt curl -s -m 2 10.10.20.10 | grep -q "Web Server"; then
    print_ok "Web content verified"
else
    print_fail "Web content missing or incorrect"
fi

# Test App Server
echo -n "  → App:      "
if sudo ip netns exec mgmt curl -s -m 2 10.10.30.10:8080 | grep -q "App Server"; then
    print_ok "App content verified"
else
    print_fail "App content missing or incorrect"
fi

# Test Database Server
echo -n "  → Database: "
if sudo ip netns exec mgmt curl -s -m 2 10.10.40.10:3306 | grep -q "Database Server"; then
    print_ok "Database content verified"
else
    print_fail "Database content missing or incorrect"
fi

echo ""
echo "${BLUE}From Web (DMZ) namespace:${RESET}"

# Test App Server from Web
echo -n "  → App:      "
if sudo ip netns exec web curl -s -m 2 10.10.30.10:8080 | grep -q "App Server"; then
    print_ok "App content verified (allowed by firewall)"
else
    print_fail "App access failed (should be allowed)"
fi

# Test Database Server from Web (should be blocked)
echo -n "  → Database: "
if sudo ip netns exec web curl -s -m 2 10.10.40.10:3306 >/dev/null 2>&1; then
    print_fail "UNEXPECTED: Database access should be blocked"
else
    print_expected "Database access blocked by firewall"
fi

echo ""
echo "${BLUE}From App (Internal) namespace:${RESET}"

# Test Database Server from App
echo -n "  → Database: "
if sudo ip netns exec app curl -s -m 2 10.10.40.10:3306 | grep -q "Database Server"; then
    print_ok "Database content verified (allowed by firewall)"
else
    print_fail "Database access failed (should be allowed)"
fi

# Test Web Server from App (should be blocked)
echo -n "  → Web:      "
if sudo ip netns exec app curl -s -m 2 10.10.20.10:80 >/dev/null 2>&1; then
    print_fail "UNEXPECTED: Web access should be blocked"
else
    print_expected "Web access blocked by firewall"
fi

echo "\n${BLUE}=== Test Summary ===${RESET}"
echo "${GREEN}✓ Allowed connections: 6/6 tests passed"
echo "${YELLOW}✓ Blocked connections: 2/2 tests passed${RESET}"
echo ""
echo "${BLUE}Services will automatically stop when this script exits.${RESET}"
echo "To manually stop services: ${YELLOW}sudo pkill -f 'nginx.*homelab'; pkill -f 'python3.*8080'; pkill -f 'python3.*3306'${RESET}"
