FROM mcr.microsoft.com/devcontainers/base:ubuntu

ARG FLUTTER_VERSION=3.44.8

ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${PATH}"
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        unzip \
        xz-utils \
        zip \
        tzdata \
        openjdk-17-jdk \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_HOME}" \
    && chown -R vscode:vscode "${FLUTTER_HOME}"

RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools \
    && mv /tmp/cmdline-tools/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest" \
    && yes | "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "platforms;android-34" "build-tools;34.0.0" "cmdline-tools;latest" \
    && yes | "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" "platforms;android-35" "build-tools;35.0.0" \
    && chown -R vscode:vscode "${ANDROID_HOME}"
