# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t blacklightning .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name blacklightning blacklightning

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version. You don't need to include the patch part.
ARG RUBY_VERSION=4.0
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    RAILS_LOG_TO_STDOUT="1" \
    RAILS_SERVE_STATIC_FILES="true"

# Install base packages and clean up in single layer
RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      libjemalloc2 \
      libvips \
      default-mysql-client \
      tzdata \
      cron && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems and node modules
RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libmariadb-dev-compat \
      pkg-config \
      curl && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

# Install Node.js for jsbundling-rails
ARG NODE_VERSION=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs

# Install application gems (persist directly in image layer so runtime
# containers have access without requiring cache mounts)
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    (bundle info bootsnap >/dev/null 2>&1 && bundle exec bootsnap precompile --gemfile || echo "Skipping bootsnap precompile") && \
    find "${BUNDLE_PATH}" -name "*.c" -delete && \
    find "${BUNDLE_PATH}" -name "*.o" -delete

# Install JavaScript dependencies
COPY package.json yarn.lock* ./
RUN npm install -g yarn && yarn install --frozen-lockfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times if available. If the
# executable isn't present we fall back gracefully so the build doesn't
# abort (this can happen in some cross-platform scenarios).
RUN (bundle info bootsnap >/dev/null 2>&1 && \
      bundle exec bootsnap precompile -j 0 app/ lib/) || \
    echo "[Dockerfile] Skipping bootsnap precompile – executable not available"

# Adjust binfiles to be executable on Linux
RUN chmod +x bin/* && \
    sed -i "s/\r$//g" bin/* && \
    sed -i 's/ruby\.exe$/ruby/' bin/*

# Precompile assets for production without requiring the real master key
 # DATABASE_URL="mysql2://user:pass@127.0.0.1:3306/dummy" 
RUN ACTIVE_STORAGE_SERVICE=local SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Clean up build artifacts
RUN rm -rf \
      node_modules \
      tmp/cache \
      /tmp/* \
      /var/tmp/*

# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /rails/tmp /rails/log && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Add health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:80/up || exit 1

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]