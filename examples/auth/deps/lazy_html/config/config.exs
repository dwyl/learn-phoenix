import Config

# We disable the extra newline in test env, because it breaks doctests.
config :lazy_html, :inspect_extra_newline, config_env() != :test
