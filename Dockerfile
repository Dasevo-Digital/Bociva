# Bociva-Server samt Weboberfläche.
# Vorher einmal die Weboberfläche bauen: app/tool/build_web.sh
# Bauen aus dem Repository-Wurzelverzeichnis: docker build -t bociva-server .
FROM dart:3.13.7@sha256:ca3ef5fe9194012074a24b03515b2c5b58dd7d4ae8c87bf463d61b5d0647f426 AS build
WORKDIR /src
COPY packages/bociva_shared packages/bociva_shared
COPY server/pubspec.* server/
WORKDIR /src/server
RUN dart pub get
COPY server .
RUN dart build cli -t bin/server.dart -o /out \
    && mkdir -p /out/data /out/keys \
    && if [ -f web/index.html ]; then cp -R web /out/bundle/web; fi

# Nur das Programmpaket, für die Installation ohne Docker (deploy/lxc).
FROM scratch AS bundle
COPY --from=build /out/bundle /bundle

# Distroless: nur glibc und CA-Zertifikate, keine Shell.
FROM gcr.io/distroless/cc-debian12@sha256:e5d81ddde149641e2a9ba55be4545bc125c67de07508b03ba4c22e6eb0ded5aa
COPY --from=build /out/bundle /opt/bociva
COPY --from=build --chown=65532:65532 /out/data /data
COPY --from=build --chown=65532:65532 /out/keys /keys
ENV BOCIVA_DATA_DIR=/data
ENV BOCIVA_KEY_FILE=/keys/bociva.key
USER 65532:65532
VOLUME /data /keys
EXPOSE 8770
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["/opt/bociva/bin/server", "--healthcheck"]
ENTRYPOINT ["/opt/bociva/bin/server"]
