# syntax=docker/dockerfile:1
# check=error=true

# Production image, for Kamal or build'n'run by hand (the dev container is .devcontainer/):
# docker build -t blacklightning .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name blacklightning blacklightning

ARG RUBY_VERSION=4.0.2
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    RAILS_LOG_TO_STDOUT="1" \
    RAILS_SERVE_STATIC_FILES="true"

# libheif-plugin-libde265 lets libvips decode the HEVC inside a HEIC (iOS photos), which receipts
# convert to JPEG (Reimbursements::ReceiptIntake). Debian's libvips pulls it in as a dependency,
# but it is named explicitly so a packaging change can't turn every iPhone receipt into "we
# couldn't read that photo". Keep in step with .devcontainer/Dockerfile.dev and CI, where it is
# not implied (Ubuntu ships libheif without a codec plugin).
RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      libjemalloc2 \
      libvips \
      libheif-plugin-libde265 \
      poppler-utils \
      default-mysql-client \
      tzdata \
      cron && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

FROM base AS build

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libmariadb-dev-compat \
      libyaml-dev \
      pkg-config \
      curl && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

# The Node major comes from .node-version (shared with mise/config.toml and the dev container), so
# production can't drift from what developers and CI run. Don't add an ARG NODE_VERSION.
COPY .node-version ./
RUN curl -fsSL "https://deb.nodesource.com/setup_$(cut -d. -f1 < .node-version).x" | bash - && \
    apt-get install -y nodejs

# Gems persist in the image layer, so runtime containers need no cache mounts.
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    (bundle info bootsnap >/dev/null 2>&1 && bundle exec bootsnap precompile --gemfile || echo "Skipping bootsnap precompile") && \
    find "${BUNDLE_PATH}" -name "*.c" -delete && \
    find "${BUNDLE_PATH}" -name "*.o" -delete

COPY package.json pnpm-lock.yaml* pnpm-workspace.yaml* ./
RUN npm install -g pnpm && pnpm install --frozen-lockfile

COPY . .

# Precompile bootsnap for faster boots; skipped if the executable is missing (some cross-platform builds).
RUN (bundle info bootsnap >/dev/null 2>&1 && \
      bundle exec bootsnap precompile -j 0 app/ lib/) || \
    echo "[Dockerfile] Skipping bootsnap precompile – executable not available"

# Make binstubs run on Linux: exec bit, CRLF line endings, Windows `ruby.exe` shebangs.
ENV PATH="/rails/bin:${PATH}"
RUN chmod +x bin/* && \
    sed -i "s/\r$//g" bin/* && \
    sed -i 's/ruby\.exe$/ruby/' bin/*

# Precompile assets for production without requiring the real master key
 # DATABASE_URL="mysql2://user:pass@127.0.0.1:3306/dummy" 
RUN ACTIVE_STORAGE_SERVICE=local SECRET_KEY_BASE_DUMMY=1 rails assets:precompile

RUN rm -rf \
      node_modules \
      tmp/cache \
      /tmp/* \
      /var/tmp/*

FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails
ENV PATH="/rails/bin:${PATH}"

# Run as a non-root user that owns only the runtime directories.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /rails/tmp /rails/log && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:80/up || exit 1

# Entrypoint prepares the database.
ENTRYPOINT ["docker-entrypoint"]

# Thruster by default; overridable at runtime.
EXPOSE 80
CMD ["thrust", "rails", "server"]
