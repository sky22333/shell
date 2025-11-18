FROM alpine:latest AS downloader

RUN apk add --no-cache wget

# ImmortalWrt版本
ARG IMWRT_VERSION=24.10.4
ARG TARGETARCH

# 根据TARGETARCH变量自动适配架构
RUN case "${TARGETARCH}" in \
        amd64) \
            URL="https://downloads.immortalwrt.org/releases/${IMWRT_VERSION}/targets/x86/64/immortalwrt-${IMWRT_VERSION}-x86-64-rootfs.tar.gz" \
            ;; \
        arm64) \
            URL="https://downloads.immortalwrt.org/releases/${IMWRT_VERSION}/targets/armsr/armv8/immortalwrt-${IMWRT_VERSION}-armsr-armv8-rootfs.tar.gz" \
            ;; \
        *) \
            echo "错误：不支持的架构 ${TARGETARCH}" && exit 1 \
            ;; \
    esac && \
    echo "开始下载 ImmortalWrt rootfs，版本：${IMWRT_VERSION}，架构：${TARGETARCH}" && \
    wget -O /rootfs.tar.gz "$URL" && \
    mkdir -p /rootfs && \
    tar -xzf /rootfs.tar.gz -C /rootfs

FROM scratch

COPY --from=downloader /rootfs/ /

WORKDIR /

CMD ["/sbin/init"]
