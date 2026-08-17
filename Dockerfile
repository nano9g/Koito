ARG NODE_VERSION=26
ARG GO_VERSION=1.26
ARG ALPINE_VERSION=3.24

# ---- Frontend build ----
FROM node:${NODE_VERSION}-alpine${ALPINE_VERSION} AS frontend

# Enable if testing only backend build
# RUN mkdir -p /client/build

ARG KOITO_VERSION=dev

ENV VITE_KOITO_VERSION=${KOITO_VERSION} \
    BUILD_TARGET=docker

WORKDIR /client

RUN npm install -g corepack && \
    corepack enable && \
    corepack prepare yarn@4 --activate

COPY ./client/ .

RUN yarn set version stable && \
    yarn install

RUN yarn run build

RUN find ./build/client -type f \( -name "*.js" -o -name "*.css" -o -name "*.html" -o -name "*.svg" \) -exec gzip -k -9 {} \;


# ---- Backend build ----
FROM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS backend

# Enable if testing only frontend build
# RUN mkdir -p /out/app

ARG KOITO_VERSION=dev

ENV CGO_ENABLED=1 \
    GOOS=linux

WORKDIR /src

RUN apk add --no-cache \
    build-base \
    pkgconfig \
    vips-dev

COPY go.mod go.sum ./

RUN go mod download

COPY . .

RUN mkdir -p /out && \
    go build \
      -trimpath \
      -buildvcs=false \
      -ldflags="-s -w -X main.Version=${KOITO_VERSION}" \
      -o /out/app \
      ./cmd/api


# ---- Runtime ----
FROM alpine:${ALPINE_VERSION} AS final

ARG UID=80003
ARG GID=80003
ENV UID=${UID}
ENV GID=${GID}

ARG KOITO_CONFIG_DIR=/config
ENV KOITO_CONFIG_DIR=${KOITO_CONFIG_DIR}

RUN apk add --no-cache vips ca-certificates && \
    addgroup -g ${GID} -S koito && \
    adduser -u ${UID} -S -D -H -G koito koito && \
    mkdir -p ${KOITO_CONFIG_DIR} /app && \
    chown koito:koito ${KOITO_CONFIG_DIR}

WORKDIR /app

COPY --from=backend /out/app ./app
COPY --from=frontend /client/build ./client/build
COPY assets/ ./assets/

VOLUME ["/config"]

EXPOSE 4110

USER ${UID}:${GID}

ENTRYPOINT ["./app"]
