#!/bin/bash
# Install the tools the EKS Auto Mode demo needs: tmux and eks-node-viewer (checks kubectl,
# and optionally the AWS CLI + Session Manager plugin used by scripts/tunnel.sh).
# Works on macOS (Homebrew) and on Linux, including the EKS Workshop browser IDE
# (downloads the eks-node-viewer release binary, no Go or Homebrew required).

set -e

EKS_NODE_VIEWER_VERSION="${EKS_NODE_VIEWER_VERSION:-v0.7.4}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
OS="$(uname -s)"
MISSING=0

echo "=== EKS Auto Mode Demo: tool setup (${OS}) ==="
echo ""

install_linux_binary() {
  local url="$1" name="$2"
  mkdir -p "${BIN_DIR}"
  curl -fsSL -o "${BIN_DIR}/${name}" "${url}"
  chmod +x "${BIN_DIR}/${name}"
  case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *) echo "   Add ${BIN_DIR} to your PATH: export PATH=\"${BIN_DIR}:\$PATH\"" ;;
  esac
}

# --- eks-node-viewer ---
echo ">> eks-node-viewer"
if command -v eks-node-viewer &>/dev/null; then
  echo "   ✓ already installed"
elif [ "${OS}" = "Darwin" ] && command -v brew &>/dev/null; then
  brew install aws/tap/eks-node-viewer && echo "   ✓ installed via Homebrew"
elif [ "${OS}" = "Linux" ]; then
  case "$(uname -m)" in
    x86_64)        ARCH="x86_64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "   ✗ unsupported CPU $(uname -m)"; MISSING=1; ARCH="" ;;
  esac
  if [ -n "${ARCH}" ]; then
    install_linux_binary \
      "https://github.com/awslabs/eks-node-viewer/releases/download/${EKS_NODE_VIEWER_VERSION}/eks-node-viewer_Linux_${ARCH}" \
      eks-node-viewer
    echo "   ✓ installed ${EKS_NODE_VIEWER_VERSION} to ${BIN_DIR}"
  fi
else
  echo "   ✗ install manually: https://github.com/awslabs/eks-node-viewer"
  MISSING=1
fi
echo ""

# --- tmux ---
echo ">> tmux"
if command -v tmux &>/dev/null; then
  echo "   ✓ already installed ($(tmux -V))"
elif [ "${OS}" = "Darwin" ] && command -v brew &>/dev/null; then
  brew install tmux && echo "   ✓ installed via Homebrew"
elif command -v dnf &>/dev/null; then
  sudo dnf install -y tmux && echo "   ✓ installed via dnf"
elif command -v yum &>/dev/null; then
  sudo yum install -y tmux && echo "   ✓ installed via yum"
elif command -v apt-get &>/dev/null; then
  sudo apt-get update -qq && sudo apt-get install -y tmux && echo "   ✓ installed via apt"
else
  echo "   ✗ install tmux with your package manager"
  MISSING=1
fi
echo ""

# --- kubectl (normally present in the EKS Workshop IDE) ---
echo ">> kubectl"
if command -v kubectl &>/dev/null; then
  echo "   ✓ already installed"
else
  echo "   ✗ kubectl not found: https://kubernetes.io/docs/tasks/tools/"
  MISSING=1
fi
echo ""

# --- Optional: only needed for the private API endpoint (scripts/tunnel.sh) ---
echo ">> aws CLI + Session Manager plugin (optional, for ./scripts/tunnel.sh)"
command -v aws &>/dev/null && echo "   ✓ aws CLI" || echo "   - aws CLI not found: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
command -v session-manager-plugin &>/dev/null && echo "   ✓ session-manager-plugin" || \
  echo "   - session-manager-plugin not found: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
echo ""

if [ ${MISSING} -eq 0 ]; then
  echo "=== All required tools are installed ==="
else
  echo "=== Some tools are missing, see above ==="
  exit 1
fi
