# Configure ExUnit
ExUnit.start(exclude: [:skip])

# Start the application for integration tests
# But we don't start the full app in tests to avoid port conflicts
Application.ensure_all_started(:req)

# You can exclude external API tests with: mix test --exclude external
