#!/bin/bash
# Install visualization tools for the EKS Auto Mode demo
# Run once before the demo to ensure all tools are available.

set -e

echo "=== EKS Auto Mode Demo — Tool Setup ==="
echo ""

MISSING=0

# --- eks-node-viewer ---
echo ">> Checking eks-node-viewer..."
if command -v eks-node-viewer &>/dev/null; then
  echo "   ✓ eks-node-viewer already installed ($(eks-node-viewer --version 2>/dev/null || echo 'version unknown'))"
else
  echo "   ✗ eks-node-viewer not found. Installing via Go..."
  if command -v go &>/dev/null; then
    go install github.com/awslabs/eks-node-viewer/cmd/eks-node-viewer@latest
    echo "   ✓ Installed. Make sure $(go env GOPATH)/bin is in your PATH."
  elif command -v brew &>/dev/null; then
    echo "   Trying Homebrew..."
    brew install aws/tap/eks-node-viewer 2>/dev/null || {
      echo "   ✗ Homebrew tap not available. Install Go first: brew install go"
      MISSING=1
    }
  else
    echo "   ✗ Neither Go nor Homebrew found. Install Go: https://go.dev/dl/"
    MISSING=1
  fi
fi

echo ""

# --- k9s ---
echo ">> Checking k9s..."
if command -v k9s &>/dev/null; then
  echo "   ✓ k9s already installed ($(k9s version --short 2>/dev/null || echo 'version unknown'))"
else
  echo "   ✗ k9s not found. Installing..."
  if command -v brew &>/dev/null; then
    brew install derailed/k9s/k9s
    echo "   ✓ Installed via Homebrew."
  else
    echo "   ✗ Homebrew not found. Install manually: https://k9scli.io/topics/install/"
    MISSING=1
  fi
fi

echo ""

# --- tmux ---
echo ">> Checking tmux..."
if command -v tmux &>/dev/null; then
  echo "   ✓ tmux already installed ($(tmux -V))"
else
  echo "   ✗ tmux not found. Installing..."
  if command -v brew &>/dev/null; then
    brew install tmux
    echo "   ✓ Installed via Homebrew."
  else
    echo "   ✗ Homebrew not found. Install manually: brew install tmux"
    MISSING=1
  fi
fi

echo ""

# --- kube-capacity (optional but nice) ---
echo ">> Checking kube-capacity (optional)..."
if command -v kube-capacity &>/dev/null; then
  echo "   ✓ kube-capacity already installed"
else
  echo "   ○ kube-capacity not found (optional). Install: brew install robscott/tap/kube-capacity"
fi

echo ""

# --- Summary ---
if [ $MISSING -eq 0 ]; then
  echo "=== All required tools are installed ==="
else
  echo "=== Some tools are missing — see above for install instructions ==="
  exit 1
fi
