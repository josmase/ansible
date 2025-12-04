FROM alpine:3.23.0@sha256:51183f2cfa6320055da30872f211093f9ff1d3cf06f39a0bdb212314c5dc7375

# Define default values for tools, empty values means that they lead to the latest available version being used.
ARG NODE_VERSION=""
ARG NVM_VERSION=""
ARG TERRAFORM_VERSION=""
ARG K8S_VERSION=""
ARG K9S_VERSION=""
ARG FLUX_VERSION=""

ENV DEFAULT_USER=developer

# Install necessary packages
RUN apk add --no-cache \
    openssh-client \
    curl \
    git \
    zsh \
    unzip \
    python3 \
    build-base

# Create default user
RUN adduser -D ${DEFAULT_USER}
USER ${DEFAULT_USER}
WORKDIR /home/${DEFAULT_USER}

# Set Zsh as default shell
SHELL ["/bin/zsh", "-c"]

# Install Oh My Zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

USER root

# Install Ansible
RUN apk add --no-cache ansible

#Install Terraform typescript CLI
##Install Node.js and NPM
RUN apk add --no-cache nodejs-current npm

##Install Terraform typescript CLI
RUN  node --version && \
    npm install -g cdktf-cli@latest

## Install Terraform CLI
ENV TERRAFORM_VERSION=${TERRAFORM_VERSION}
RUN if [ -z "$TERRAFORM_VERSION" ]; then \
    TERRAFORM_VERSION=$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest | grep -o '"tag_name": ".*"' | cut -d'"' -f4 | sed 's/^v//'); \
    fi && \ 
    curl -sLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" && \
    unzip "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -d /usr/local/bin && \
    chmod +x "$(which terraform)" && \
    rm "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"

# Install Kubernetes CLI
ENV K8S_VERSION=${K8S_VERSION}
RUN if [ -z "$K8S_VERSION" ]; then \
    K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt); \
    fi && \
    curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl" && \
    curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl.sha256" && \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/ && \
    rm kubectl.sha256

# Install k9s
ENV K9S_VERSION=${K9S_VERSION}
RUN if [ -z "$K9S_VERSION" ]; then \
    K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep -o '"tag_name": ".*"' | cut -d'"' -f4); \
    fi && \
    curl -LO "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" && \
    tar -zxvf k9s_Linux_amd64.tar.gz -C /usr/local/bin && \
    chmod +x "$(which k9s)" && \
    rm k9s_Linux_amd64.tar.gz

# Install Flux CLI
ENV FLUX_VERSION=${FLUX_VERSION}
RUN if [ -z "$FLUX_VERSION" ]; then \
    FLUX_VERSION=$(curl -s https://api.github.com/repos/fluxcd/flux2/releases/latest | grep -o '"tag_name": ".*"' | cut -d'"' -f4 | sed 's/^v//'); \
    fi && \
    curl -LO "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_amd64.tar.gz" && \
    tar -zxvf flux_${FLUX_VERSION}_linux_amd64.tar.gz && \
    mv ./flux /usr/local/bin/ && \
    chmod +x "$(which flux)" && \
    rm flux_${FLUX_VERSION}_linux_amd64.tar.gz

# Switch back to default user
USER ${DEFAULT_USER}
WORKDIR /home/${DEFAULT_USER}
