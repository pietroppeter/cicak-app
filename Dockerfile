# The playground compiles cells at run time, so the image ships Nim and a C compiler.
# Nim 2.4 is built from source: hot code reloading crashes on 2.2, and the 2.4.0
# release binaries lack nifler, which `nim ic` needs. Disco caches this layer, so
# only the first build (or a NIM_REF change) pays for it.
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev make git ca-certificates wget \
 && rm -rf /var/lib/apt/lists/*

ARG NIM_REF=version-2-4
ENV NIM_DIR=/opt/nim
RUN git clone --depth 1 -b "$NIM_REF" https://github.com/nim-lang/Nim "$NIM_DIR" \
 && cd "$NIM_DIR" \
 && . config/build_config.txt \
 && git clone -q "$nim_csourcesUrl" "$nim_csourcesDir" \
 && git -C "$nim_csourcesDir" checkout -q "$nim_csourcesHash" \
 && make -C "$nim_csourcesDir" -j"$(nproc)" \
 && ./bin/nim c --hints:off --skipUserCfg --skipParentCfg koch \
 && ./koch boot -d:release --skipUserCfg --skipParentCfg \
 && rm -rf "$nim_csourcesDir" nimcache ~/.cache/nim \
 && ls bin
ENV PATH=/opt/nim/bin:$PATH

# The two runtime libraries hot code reloading needs, built once here. Nim has no
# HCR jump table for arm64 Linux (e.g. Docker on Apple Silicon): there the build
# fails, the image is built anyway, and the page shows that error for hot reload.
ENV RTL_DIR=/opt/nim-rtl
RUN mkdir -p "$RTL_DIR" && cd "$RTL_DIR" \
 && { nim c --hints:off --warnings:off --app:lib -d:createNimRtl --out:libnimrtl.so "$NIM_DIR/lib/nimrtl.nim" \
   && nim c --hints:off --warnings:off --app:lib -d:createNimHcr --out:libnimhcr.so "$NIM_DIR/lib/nimhcr.nim" \
   || { echo "hot code reloading is not available on $(uname -m)"; rm -f libnimrtl.so libnimhcr.so; }; } \
 && rm -rf ~/.cache/nim

WORKDIR /app
COPY deps.sh nim.cfg ./
RUN ./deps.sh
COPY src ./src
RUN nim c -d:release --hints:off -o:/app/cicak_app src/cicak_app.nim
COPY notebooks ./notebooks

RUN useradd -m -u 1000 app && mkdir -p /work && chown app:app /work "$RTL_DIR"
USER app
ENV PORT=8000 WORK_DIR=/work NOTEBOOKS_DIR=/app/notebooks
EXPOSE 8000
CMD ["/app/cicak_app"]
