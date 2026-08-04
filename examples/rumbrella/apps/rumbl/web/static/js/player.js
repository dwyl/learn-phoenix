let Player = {  // JS works for small scripts like this
  player: null, // but for anything bigger we prefer Elm
                // and so do the creators of Phoenix!
                // see: https://github.com/dwyl/learn-elm
  init(domId, playerId, onReady) {
    window.onYouTubeIframeAPIReady = () => {
      this.onIFrameReady(domId, playerId, onReady)
    }
    let youtubeScriptTag = document.createElement("script")
    youtubeScriptTag.src = "//www.youtube.com/iframe_api"
    document.head.appendChild(youtubeScriptTag)
  },

  onIFrameReady(domId, playerId, onReady) {
    this.player = new YT.Player(domId, {
      height: "360",
      width: "420",
      videoId: playerId,
      events: {
        "onReady": (event => onReady(event)),
        "onStateChange": (event => this.onPlayerStateChange(event))
      }
    })
  },

  onPlayerStateChange(event) { },
  getCurrentTime(){ return Math.floor(this.player.getCurrentTime() * 1000) },
  seekTo(millsec) { return this.player.seekTo(millsec / 1000) }

}
export default Player
