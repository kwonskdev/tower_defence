# Lane Wars 서버 이미지 (#24). 미리 빌드한 Linux 서버 바이너리를 담는다 (빌드: tools/server/build.sh -> build/server/lanewars-server.x86_64).
# 빌드 컨텍스트는 저장소 루트:  docker build -f deploy/Dockerfile -t lanewars-server .
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --uid 10001 lanewars
WORKDIR /srv/lanewars
COPY --chown=lanewars:lanewars build/server/lanewars-server.x86_64 ./lanewars-server.x86_64
RUN chmod +x ./lanewars-server.x86_64
USER lanewars
ENV PORT=47300
EXPOSE 47300
# 포트가 열려 있는지만 본다 (방/접속자 수는 로그의 METRICS 줄)
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/${PORT}' || exit 1
# 서버 옵션은 command로 덧붙인다 (docker-compose.yml 참고). 로그는 표준 출력으로 나온다 (docker logs).
ENTRYPOINT ["/bin/sh", "-c", "exec ./lanewars-server.x86_64 --headless --server --port=${PORT} \"$@\"", "--"]
CMD ["--max-rooms=64", "--max-rooms-per-addr=64", "--metrics-interval=60"]
