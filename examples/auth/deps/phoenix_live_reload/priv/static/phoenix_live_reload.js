let getFreshUrl = (url) => {
  let date = Math.round(Date.now() / 1000).toString()
  let cleanUrl = url.replace(/(&|\?)vsn=\d*/, "")
  let freshUrl = cleanUrl + (cleanUrl.indexOf("?") >= 0 ? "&" : "?") + "vsn=" + date
  return freshUrl;
}

let buildFreshLinkUrl = (link) => {
  let newLink = document.createElement('link')
  let onComplete = () => {
    if(link.parentNode !== null){
      link.parentNode.removeChild(link)
    }
  }

  newLink.onerror = onComplete
  newLink.onload  = onComplete
  link.setAttribute("data-pending-removal", "")
  newLink.setAttribute("rel", "stylesheet")
  newLink.setAttribute("type", "text/css")
  newLink.setAttribute("href", getFreshUrl(link.href))
  link.parentNode.insertBefore(newLink, link.nextSibling)
  return newLink
}

let buildFreshImportUrl = (style) => {
  let newStyle = document.createElement('style')
  let onComplete = () => {
    if (style.parentNode !== null) {
      style.parentNode.removeChild(style)
    }
  }

  let originalCSS = style.textContent || style.innerHTML
  let freshCSS = originalCSS.replace(/@import\s+(?:url\()?['"]?([^'"\)]+)['"]?\)?/g, (match, url) => {
    const freshUrl = getFreshUrl(url);

    if (match.includes('url(')) {
      return `@import url("${freshUrl}")`
    } else {
      return `@import "${freshUrl}"`
    }
  })

  newStyle.onerror = onComplete
  newStyle.onload = onComplete
  style.setAttribute("data-pending-removal", "")
  newStyle.setAttribute("type", "text/css")
  newStyle.textContent = freshCSS

  style.parentNode.insertBefore(newStyle, style.nextSibling)
  return newStyle
}

let repaint = () => {
  let browser = navigator.userAgent.toLowerCase()
  if (browser.indexOf("chrome") > -1) {
    setTimeout(() => document.body.offsetHeight, 25)
  }
}

let cssStrategy = () => {
  let reloadableLinkElements = window.parent.document.querySelectorAll(
    "link[rel=stylesheet]:not([data-no-reload]):not([data-pending-removal])"
  )

  Array.from(reloadableLinkElements)
    .filter(link => link.href)
    .forEach(link => buildFreshLinkUrl(link))

  let reloadablestyles = window.parent.document.querySelectorAll(
    "style:not([data-no-reload]):not([data-pending-removal])"
  )

  Array.from(reloadablestyles)
    .filter(style => style.textContent.includes("@import"))
    .forEach(style => buildFreshImportUrl(style))

  repaint()
};

let pageStrategy = channel => {
  channel.off("assets_change")
  window[targetWindow].location.reload()
}

let reloadStrategies = {
  css: reloadPageOnCssChanges ? pageStrategy : cssStrategy,
  page: pageStrategy
};

class LiveReloader {
  constructor(socket){
    this.socket = socket
    this.logsEnabled = false
    this.enabledOnce = false
    this.editorURL = null
  }
  enable(){
    this.socket.onOpen(() => {
      if(this.enabledOnce){ return }
      this.enabledOnce = true
      if(["complete", "loaded", "interactive"].indexOf(parent.document.readyState) >= 0){
        this.dispatchConnected()
      } else {
        parent.addEventListener("load", () => this.dispatchConnected())
      }
    })

    this.channel = socket.channel("phoenix:live_reload", {})
    this.channel.on("assets_change", msg => {
      let reloadStrategy = reloadStrategies[msg.asset_type] || reloadStrategies.page
      setTimeout(() => reloadStrategy(this.channel), interval)
    })
    this.channel.on("log", ({msg, level}) => this.logsEnabled && this.log(level, msg))
    this.channel.join().receive("ok", ({editor_url}) => {
      this.editorURL = editor_url
    })
    this.socket.connect()
  }

  disable(){
    this.channel.leave()
    socket.disconnect()
  }

  enableServerLogs(){ this.logsEnabled = true }
  disableServerLogs(){ this.logsEnabled = false }

  openEditorAtCaller(targetNode){
    if(!this.editorURL){
      return console.error("phoenix_live_reload cannot openEditorAtCaller without configured PLUG_EDITOR")
    }

    let fileLineApp = this.closestCallerFileLine(targetNode)
    if(fileLineApp){
      this.openFullPath(...fileLineApp)
    }
  }

  openEditorAtDef(targetNode){
    if(!this.editorURL){
      return console.error("phoenix_live_reload cannot openEditorAtDef without configured PLUG_EDITOR")
    }

    let fileLineApp = this.closestDefFileLine(targetNode)
    if(fileLineApp){
      this.openFullPath(...fileLineApp)
    }
  }

  // private

  openFullPath(file, line, app){
    console.log("opening full path", file, line, app)
    this.channel.push("full_path", {rel_path: file, app: app})
      .receive("ok", ({full_path}) => {
        console.log("full path", full_path)
        let url = this.editorURL
          .replace("__RELATIVEFILE__", file)  
          .replace("__FILE__", full_path)
          .replace("__LINE__", line)
        window.open(url, "_self")
      })
      .receive("error", reason => console.error("failed to resolve full path", reason))
  }

  dispatchConnected(){
    parent.dispatchEvent(new CustomEvent("phx:live_reload:attached", {detail: this}))
  }

  log(level, str){
    let levelColor = level === "debug" ? "darkcyan" : "inherit"
    let consoleFunc = this.logFunc(level)
    this.logMsg(consoleFunc, str, levelColor)
  }

  logMsg(fun, str, color) {
    fun(`%c📡 ${str}`, `color: ${color};`)
  }
  
  logFunc(level){
    switch(level) {
      case "debug":
        return console.debug;
      case "info":
        return console.info;
      case "warning":
        return console.warn;
      default:
        return console.error;
    }
  }

  closestCallerFileLine(node){
    while(node.previousSibling){
      node = node.previousSibling
      if(node.nodeType === Node.COMMENT_NODE){
        let callerComment = node.previousSibling
        let callerMatch = callerComment &&
          callerComment.nodeType === Node.COMMENT_NODE &&
          callerComment.nodeValue.match(/\s@caller\s+(.+):(\d+)\s\((.*)\)\s/i)

        if(callerMatch){
          return [callerMatch[1], callerMatch[2], callerMatch[3]]
        }
      }
    }
    if(node.parentNode){ return this.closestCallerFileLine(node.parentNode) }
  }

  closestDefFileLine(node){
    while(node.previousSibling){
      node = node.previousSibling
      if(node.nodeType === Node.COMMENT_NODE){
        let fcMatch = node.nodeValue.match(/.*>\s([\w\/]+.*ex):(\d+)\s\((.*)\)\s/i)
        if(fcMatch){
          return [fcMatch[1], fcMatch[2], fcMatch[3]]
        }
      }
    }
    if(node.parentNode){ return this.closestDefFileLine(node.parentNode) }
  }
}

reloader = new LiveReloader(socket)
reloader.enable()
