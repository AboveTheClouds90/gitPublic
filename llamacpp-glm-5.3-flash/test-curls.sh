#!/usr/bin/env bash
# Run on the VM, or set HOST to the VM's IP: HOST=192.168.1.50 ./test-curls.sh
HOST=${HOST:-localhost}

# 1. Is the server up? Expect {"status":"ok"}
curl http://$HOST:8080/health
echo

# 2. Which model is loaded? Expect "glm-5.3-flash"
curl http://$HOST:8080/v1/models
echo

# 3. Ask it something
curl http://$HOST:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-5.3-flash",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}]
  }'
echo
