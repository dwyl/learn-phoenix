Code.require_file "backends/http_client.exs", __DIR__
ExUnit.start(assert_receive_timeout: 300) # default is 100ms, increasing to 300ms
# due to encountering this issue: https://github.com/phoenixframework/phoenix/issues/2023

