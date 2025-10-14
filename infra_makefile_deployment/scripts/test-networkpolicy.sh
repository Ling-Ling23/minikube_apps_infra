#!/bin/bash
# Test script to verify NetworkPolicy is working

echo "=== Testing NetworkPolicy for py3miniapp-backend ==="
echo

# Get backend pod info
BACKEND_POD=$(kubectl get pods -l app=py3miniapp-backend -o jsonpath='{.items[0].metadata.name}')
BACKEND_IP=$(kubectl get pods -l app=py3miniapp-backend -o jsonpath='{.items[0].status.podIP}')

echo "Backend Pod: $BACKEND_POD"
echo "Backend IP: $BACKEND_IP"
echo

# Test 1: Test access from ingress controller (should work)
echo "=== Test 1: Access from NGINX Ingress Controller (should ALLOW) ==="
INGRESS_POD=$(kubectl get pods -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.name}')
echo "Testing from ingress pod: $INGRESS_POD"
kubectl exec $INGRESS_POD -- curl -s --connect-timeout 5 http://$BACKEND_IP/live || echo "Connection failed (as expected if policy is working)"
echo

# Test 2: Test access from a random pod (should be blocked)
echo "=== Test 2: Access from random pod (should DENY) ==="
echo "Creating test pod..."
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -- sh -c "
echo 'Testing direct connection to backend pod...'
curl -s --connect-timeout 5 http://$BACKEND_IP/live && echo 'SUCCESS: Could reach backend' || echo 'BLOCKED: Could not reach backend (NetworkPolicy working!)'
" || echo "Test pod execution completed"

echo
echo "=== Test 3: Access via Service (through ingress, should work) ==="
echo "Testing via ingress URL..."
curl -k -s --connect-timeout 10 https://myapp.local/app1_backend/live && echo "SUCCESS: Can reach via ingress" || echo "Failed to reach via ingress"

echo
echo "=== NetworkPolicy Status ==="
kubectl describe networkpolicy py3miniapp-backend-ingress-only