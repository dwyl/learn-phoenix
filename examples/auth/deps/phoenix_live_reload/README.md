A project for live-reload functionality for [Phoenix](http://github.com/phoenixframework/phoenix) during development.

## Usage

You can use `phoenix_live_reload` in your projects by adding it to your `mix.exs` dependencies:

```elixir
def deps do
  [{:phoenix_live_reload, "~> 1.5"}]
end
```

You can configure the reloading interval in ms in your `config/dev.exs`:

```elixir
# Watch static and templates for browser reloading.
config :my_app, MyAppWeb.Endpoint,
  live_reload: [
    interval: 1000,
    patterns: [
      ...
```

The default interval is 100ms.

## Streaming serving logs to the web console

> *Note:* This feature is only available for Elixir v1.15+

Streaming server logs that you see in the terminal when running `mix phx.server` can be useful to have on the client during development, especially when debugging with SPA fetch callbacks, GraphQL queries, or LiveView actions in the browsers web console. You can enable log streaming to collocate client and server logs in the web console with the `web_console_logger` configuration in your `config/dev.exs`:

```elixir
config :my_app, MyAppWeb.Endpoint,
  live_reload: [
    interval: 1000,
    patterns: [...],
    web_console_logger: true
  ]
```

Next, you'll need to listen for the `"phx:live_reload:attached"` event and enable client logging by calling the reloader's `enableServerLogs()` function, for example:

```javascript
window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
  // enable server log streaming to client.
  // disable with reloader.disableServerLogs()
  reloader.enableServerLogs()
})
```

## Jumping to HEEx function definitions

Many times it's useful to inspect the HTML DOM tree to find where markup is being rendered from within your application. HEEx supports annotating rendered HTML with HTML comments that give you the file/line of a HEEx function component and caller. `:phoenix_live_reload` will look for the `PLUG_EDITOR` environment export (used by the plug debugger page to link to source code) to launch a configured URL of your choice to open your code editor to the file-line of the HTML annotation. For example, the following export on your system would open vscode at the correct file/line:

```
export PLUG_EDITOR="vscode://file/__FILE__:__LINE__"
```

The `vscode://` protocol URL will open vscode with placeholders of `__FILE__:__LINE__` substituted at runtime. Check your editor's documentation on protocol URL support. To open your configured editor URL when an element is clicked, say with alt-click, you can wire up an event listener within your `"phx:live_reload:attached"` callback and make use of the reloader's `openEditorAtCaller` and `openEditorAtDef` functions, passing the event target as the DOM node to reference for HEEx file:line annotation information. For example:

```javascript
window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
  // Enable server log streaming to client. Disable with reloader.disableServerLogs()
  reloader.enableServerLogs()

  // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
  //
  //   * click with "c" key pressed to open at caller location
  //   * click with "d" key pressed to open at function component definition location
  let keyDown
  window.addEventListener("keydown", e => keyDown = e.key)
  window.addEventListener("keyup", e => keyDown = null)
  window.addEventListener("click", e => {
    if(keyDown === "c"){
      e.preventDefault()
      e.stopImmediatePropagation()
      reloader.openEditorAtCaller(e.target)
    } else if(keyDown === "d"){
      e.preventDefault()
      e.stopImmediatePropagation()
      reloader.openEditorAtDef(e.target)
    }
  }, true)
  window.liveReloader = reloader
})
```

## Backends

This project uses [`FileSystem`](https://github.com/falood/file_system) as a dependency to watch your filesystem whenever there is a change and it supports the following operating systems:

* Linux via [inotify](https://github.com/rvoicilas/inotify-tools/wiki) (installation required)
* Windows via [inotify-win](https://github.com/thekid/inotify-win) (no installation required)
* Mac OS X via fsevents (no installation required)
* FreeBSD/OpenBSD/~BSD via [inotify](https://github.com/rvoicilas/inotify-tools/wiki) (installation required)

There is also a `:fs_poll` backend that polls the filesystem and is available on all Operating Systems in case you don't want to install any dependency. You can configure the `:backend` in your `config/config.exs`:

```elixir
config :phoenix_live_reload,
  backend: :fs_poll
```

By default the entire application directory is watched by the backend. However, with some environments and backends, this may be inefficient, resulting in slow response times to file modifications. To account for this, it's also possible to explicitly declare a list of directories for the backend to watch (they must be relative to the project root, otherwise they are just ignored), and additional options for the backend:

```elixir
config :phoenix_live_reload,
  dirs: [
    "priv/static",
    "priv/gettext",
    "lib/example_web/live",
    "lib/example_web/views",
    "lib/example_web/templates",
    "../another_project/priv/static", # Contents of this directory is not watched
    "/another_project/priv/static", # Contents of this directory is not watched
  ],
  backend: :fs_poll,
  backend_opts: [
    interval: 500
  ]
```


## Skipping remote CSS reload

All stylesheets are reloaded without a page refresh anytime a style is detected as having changed. In certain cases such as serving stylesheets from a remote host, you may wish to prevent unnecessary reload of these stylesheets during development. For this, you can include a `data-no-reload` attribute on the link tag, ie:

    <link rel="stylesheet" href="http://example.com/style.css" data-no-reload>

## Differences between [Phoenix.CodeReloader](https://hexdocs.pm/phoenix/Phoenix.CodeReloader.html#content)

[Phoenix.CodeReloader](https://hexdocs.pm/phoenix/Phoenix.CodeReloader.html#content) recompiles code in the lib directory. This means that if you change anything in the lib directory (such as a context) then the Elixir code will be reloaded and used on your next request.

In contrast, this project adds a plug which injects some JavaScript into your page with a WebSocket connection to the server. When you make a change to anything in your config for live\_reload (JavaScript, stylesheets, templates and views by default) then the page will be reloaded in response to a message sent via the WebSocket. If the change was to an Elixir file then it will be recompiled and served when the page is reloaded. If it is JavaScript or CSS, then only assets are reloaded, without triggering a full page load.

## License

[Same license as Phoenix](https://github.com/phoenixframework/phoenix/blob/master/LICENSE.md).
