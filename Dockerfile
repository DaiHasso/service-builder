FROM golang:alpine

RUN apk update && apk add openssh git upx git

ENV GO111MODULE=on
ENV OS linux
ENV ARCH amd64

COPY files/build_flags.sh /build_flags.sh

RUN go get github.com/markbates/pkger/cmd/pkger

# === Onbuild Begin ===
# If you need custom files such as ssh keys, gitconfig, etc they can be placed
# in a scratch container with the correct file structure and they will be
# copied to this container on build.
ONBUILD COPY --from=custom_files / /

ONBUILD RUN if [ -f /root/.ssh/id_rsa ]; then chmod 700 /root/.ssh/id_rsa; fi
ONBUILD RUN if [ -f /root/.ssh/config ]; then chmod 600 /root/.ssh/config; fi

#
# PACKAGE_NAME is the fully qualified name of this service such as:
#   mycompany.com/mycoolservice
ONBUILD ARG PACKAGE_NAME

ONBUILD RUN if [ -z "$PACKAGE_NAME" ]; then echo "NOT SET - ERROR"; exit 1; fi

ONBUILD WORKDIR /go/src/${PACKAGE_NAME}
ONBUILD COPY go.mod ./
ONBUILD COPY go.sum ./

#
# Repos that are private. Set before calling go mod.
# More information on syntax here: https://tinyurl.com/yy9buq26
# Example:
#   GOPRIVATE="mycompany.com/*"
#
ONBUILD ARG GOPRIVATE

ONBUILD RUN echo "Downloading dependencies..."
ONBUILD RUN go mod download

# USE_PKGER If this variable is set pkger will be run before building.
#   1
#
# The pkger library lets you include binary files into your go binary.
# For more info see: https://github.com/markbates/pkger
ONBUILD ARG USE_PKGER

ONBUILD COPY . ./

ONBUILD RUN if [ ! -z "$USE_PKGER" ]; then echo "Running pkger..."; pkger; fi

#
# FRAMEWORK_PACKAGE is the go package which contains a Version, GitHash and SemVer
# export which will be overriden on compile-time.
# Example:
#   ARG FRAMEWORK_PACKAGE=vendor/mycompany.com/coolframework/versioning
#
# See files/build_flags.sh for more information.
#
ONBUILD ARG FRAMEWORK_PACKAGE

# All of the following args regard versioning and are completly optional.
# VERSION is the raw root version for this build in semver format (with no
# prefix or suffix) such as:
#   1.0.0
#
# This will be set to ${FRAMEWORK_PACKAGE}.Version via build flags or not set at
# all if variable is empty.
ONBUILD ARG VERSION

# GITHASH is the short hash for the current commit, this is typically used if
# the working branch is dirty. Ex:
#   e19668f
#
# This will be set to ${FRAMEWORK_PACKAGE}.GitHash via build flags or not set at
# all if variable is empty.
ONBUILD ARG GITHASH

# SEMVER is the full semver version as you want it presented such as:
#   1.0.0-alpha+exp.sha.e19668f
#
# This will be set to ${FRAMEWORK_PACKAGE}.SemVer via build flags or not set at
# all if variable is empty.
ONBUILD ARG SEMVER

ONBUILD RUN sh /build_flags.sh

ONBUILD RUN echo "Building package '${PACKAGE_NAME}'..."

ONBUILD ARG BUILD_PACKAGE

ONBUILD RUN CGO_ENABLED=0 GOOS=linux go build -a -ldflags \
        "$(cat /buildflags)-s -w" -o /app ${BUILD_PACKAGE:-.}

#
# UPX_ARGS are args passed directly into upx.
# Example:
#   UPX_ARGS="--best --ultra-brute"
#
ONBUILD ARG UPX_ARGS

ONBUILD ARG USE_UPX

ONBUILD RUN if [ ${USE_UPX:-1} -eq 1 ]; then \
            echo "Compressing binary using upx with args: $UPX_ARGS"; fi

ONBUILD RUN if [ ${USE_UPX:-1} -eq 1 ]; then \
            upx $UPX_ARGS /app &> /tmp/out.log && tail -5 /tmp/out.log | \
            head -3; fi

ONBUILD RUN echo "Copying compiled go binary to final container..."
