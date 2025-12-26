# --------------------------
# stm32cubemx + stm32tool Dockerfile
# --------------------------

FROM ubuntu:24.04

# 1. CubeMX 版本环境变量
ENV CUBEMX_VERSION="v6160"

# 2. 安装所有系统依赖 - 合并到单个RUN指令以减少层数
USER root

RUN apt-get update && apt-get install -y ca-certificates curl && update-ca-certificates

# 使用国内镜像源
RUN cp /etc/apt/sources.list /etc/apt/sources.list.bak && \
    cat <<'EOF' > /etc/apt/sources.list
# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
deb https://mirrors.osa.moe/ubuntu/ noble main restricted universe multiverse
# deb-src https://mirrors.osa.moe/ubuntu/ noble main restricted universe multiverse
deb https://mirrors.osa.moe/ubuntu/ noble-updates main restricted universe multiverse
# deb-src https://mirrors.osa.moe/ubuntu/ noble-updates main restricted universe multiverse
deb https://mirrors.osa.moe/ubuntu/ noble-backports main restricted universe multiverse
# deb-src https://mirrors.osa.moe/ubuntu/ noble-backports main restricted universe multiverse

# deb https://mirrors.osa.moe/ubuntu/ noble-security main restricted universe multiverse
# # deb-src https://mirrors.osa.moe/ubuntu/ noble-security main restricted universe multiverse

deb http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
# deb-src http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse

# 预发布软件源，不建议启用
# deb https://mirrors.osa.moe/ubuntu/ noble-proposed main restricted universe multiverse
# # deb-src https://mirrors.osa.moe/ubuntu/ noble-proposed main restricted universe multiverse
EOF

# 更新 apt 并安装基础工具
RUN apt-get update && apt-get install -y \
    curl wget git vim gnupg gnupg2 unzip jq \
    && rm -rf /var/lib/apt/lists/*

# 3. 安装 CubeMX 图形和显示依赖
RUN apt-get update -y && \
    apt-get install -y \
        xvfb \
        libgbm1 \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 5. 安装 Java 运行时环境
RUN apt-get update -y && \
    apt-get install -y \
        openjdk-21-jre \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 7. 安装构建基础工具
RUN apt-get update -y && \
    apt-get install -y \
        build-essential \
        sudo \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 8. 安装 Python 环境
RUN apt-get update -y && \
    apt-get install -y \
        python3 \
        python3-pip \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 9. 安装 Ninja 构建系统
RUN apt-get update -y && \
    apt-get install -y \
        ninja-build \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 10. 安装 ARM 工具链
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        gcc-arm-none-eabi \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 10. 安装 ARM 工具链
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        libnewlib-arm-none-eabi \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 11. 添加 Kitware APT 源并安装 CMake
RUN wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc \
    | gpg --dearmor -o /usr/share/keyrings/kitware-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ jammy main" \
    | tee /etc/apt/sources.list.d/kitware.list && \
    apt-get update && \
    apt-get install -y cmake && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 3. 创建非 root 用户并设置工作目录
RUN useradd -m -s /bin/bash stm32 && \
    mkdir -p /workspace && \
    chown -R stm32:stm32 /workspace

USER stm32
WORKDIR /home/stm32

# 4. 设置环境变量
ENV CUBE_PATH="/home/stm32/STM32CubeMX"
ENV PATH="$CUBE_PATH:/home/stm32/.local/bin:$PATH"

# 5. 下载并安装 CubeMX 到用户目录
RUN mkdir -p tmp_st && cd tmp_st && \
    wget -nv https://sw-center.st.com/packs/resource/library/stm32cube_mx_${CUBEMX_VERSION}-lin.zip && \
    unzip -q stm32cube_mx_${CUBEMX_VERSION}-lin.zip && \
    ([ -f JavaJre.zip ] && unzip -q JavaJre.zip || echo "no JavaJre.zip found") && \
    mkdir -p ../STM32CubeMX && \
    mv MX/* ../STM32CubeMX/ 2>/dev/null || true && \
    ([ -d jre ] && mv jre ../STM32CubeMX/ || echo "no jre folder found") && \
    cd .. && rm -rf tmp_st

# 6. 创建 CubeMX 启动脚本
RUN mkdir -p /home/stm32/.local/bin && \
    echo '#!/bin/bash\nexec /home/stm32/STM32CubeMX/jre/bin/java -jar /home/stm32/STM32CubeMX/STM32CubeMX "$@"' \
    > /home/stm32/.local/bin/stm32cubemx && \
    chmod +x /home/stm32/.local/bin/stm32cubemx

# 7. 初始化 CubeMX (headless)
RUN echo 'load STM32F407VETx\nexit' > cube-init && \
    xvfb-run -a stm32cubemx -q cube-init && \
    rm cube-init && \
    pkill -f Xvfb 2>/dev/null || true && \
    rm -f /tmp/.X10-lock 2>/dev/null || true

# 8. 可选：克隆 MCU 仓库
ARG MCU
RUN if [ -n "$MCU" ]; then \
        mkdir -p /home/stm32/STM32Cube/Repository && \
        cd /home/stm32/STM32Cube/Repository && \
        git clone https://github.com/STMicroelectronics/STM32Cube${MCU}.git && \
        cd STM32Cube${MCU} && \
        git submodule update --init --recursive; \
    else \
        echo "Docker built without MCU repository."; \
    fi

# 9. 安装 stm32tool 最新版本
RUN ST32TOOL_LATEST=$(curl -s https://api.github.com/repos/HITSZ-WTRobot/stm32tool/releases/latest \
        | jq -r '.assets[] | select(.name | test("stm32tool-linux-v.*")) | .browser_download_url' | head -n1) && \
    if [ -z "$ST32TOOL_LATEST" ]; then echo "Failed to get latest stm32tool URL"; exit 1; fi && \
    echo "Downloading stm32tool from $ST32TOOL_LATEST" && \
    wget -nv "$ST32TOOL_LATEST" -O /home/stm32/.local/bin/stm32tool && \
    chmod +x /home/stm32/.local/bin/stm32tool


# 10. 最终权限设置
USER root

RUN chown -R stm32:stm32 /home/stm32 && \
    chmod 755 \
        /home/stm32/STM32CubeMX/STM32CubeMX \
        /home/stm32/STM32CubeMX/jre/bin/java \
        /home/stm32/.local/bin/stm32cubemx \
        /home/stm32/.local/bin/stm32tool

USER stm32
WORKDIR /workspace

# 默认 shell
CMD ["/bin/bash"]
