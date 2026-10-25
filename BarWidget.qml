import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Spotify on the bar as a playback wave; hovering it opens a card with the
// cover, song, progress and controls, all read straight from Spotify's MPRIS
// player. Only on the bar while Spotify runs.
BarWidget {
  id: root
  moduleName: "io.github.elipserus.spotify-wave"

  readonly property var player: {
    var players = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (String(p.dbusName || "").indexOf("spotify") !== -1 || String(p.identity || "").toLowerCase() === "spotify") return p
    }
    return null
  }
  readonly property bool playing: player !== null && player.isPlaying
  readonly property string title: player ? (player.trackTitle || "") : ""
  readonly property string artist: player ? (player.trackArtist || "") : ""
  readonly property string album: player ? (player.trackAlbum || "") : ""
  readonly property string artUrl: player ? (player.trackArtUrl || "") : ""
  readonly property real length: player && player.lengthSupported ? player.length : 0
  readonly property real progress: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0
  readonly property int waveBars: 10
  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground

  // MPRIS doesn't push playback position, so sample it while playing.
  property real position: 0

  property bool popupOpen: false
  function close() { popupOpen = false; closeDelay.stop() }

  // The card follows the pointer: it opens on the wave and stays open while
  // the pointer is on either, with a short grace period to cross the gap.
  readonly property bool hovered: waveHover.hovered || popup.containsMouse
  onHoveredChanged: {
    if (hovered) {
      closeDelay.stop()
      popupOpen = true
    } else {
      closeDelay.restart()
    }
  }

  Timer {
    id: closeDelay
    interval: 300
    onTriggered: root.popupOpen = false
  }

  // Wave levels, 0..1 per bar: a light made-up motion while playing, taller
  // in the middle. It doesn't follow the audio, so it costs next to nothing.
  property var levels: []

  function syncPosition() {
    position = player && player.positionSupported ? player.position : 0
  }

  function formatTime(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    var m = Math.floor(s / 60)
    s = s % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }

  function playPause() { if (player && player.canTogglePlaying) player.togglePlaying() }
  function next() { if (player && player.canGoNext) player.next() }
  function previous() { if (player && player.canGoPrevious) player.previous() }

  function seekTo(fraction) {
    if (!player || !player.canSeek || length <= 0) return
    player.position = fraction * length
    position = fraction * length
  }

  function openSpotify() {
    close()
    Quickshell.execDetached(["omarchy-hyprland-focus-app", "spotify"])
  }

  onPlayerChanged: syncPosition()
  onTitleChanged: syncPosition()

  Timer {
    interval: 1000
    repeat: true
    running: root.playing && (root.visible || root.popupOpen)
    triggeredOnStart: true
    onTriggered: root.syncPosition()
  }

  visible: player !== null && !vertical
  onVisibleChanged: if (!visible) close()
  implicitWidth: visible ? row.implicitWidth + Style.space(16) : 0
  implicitHeight: barSize

  IpcHandler {
    target: "io.github.elipserus.spotify-wave"

    function playPause(): void { root.playPause() }
    function next(): void { root.next() }
    function previous(): void { root.previous() }
    function card(): void { if (root.visible) root.popupOpen = !root.popupOpen }
  }

  Timer {
    interval: 120
    repeat: true
    running: root.playing && root.visible
    onTriggered: {
      var next = []
      for (var i = 0; i < root.waveBars; i++) {
        var center = 1 - Math.abs(i - (root.waveBars - 1) / 2) / root.waveBars
        next.push(0.2 + Math.random() * 0.8 * center)
      }
      root.levels = next
    }
  }

  onPlayingChanged: if (!playing) levels = []

  Row {
    id: row
    anchors.centerIn: parent
    height: Math.round(root.barSize * 0.5)
    spacing: Math.max(1, Style.space(2))

    Repeater {
      model: root.waveBars

      Rectangle {
        required property int index
        readonly property real level: root.levels.length > index ? root.levels[index] : 0

        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(2, Style.space(3))
        height: Math.max(width, row.height * level)
        radius: width / 2
        color: root.foreground
        opacity: root.playing ? 0.9 : 0.45

        Behavior on height { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
      }
    }
  }

  HoverHandler {
    id: waveHover
    cursorShape: Qt.PointingHandCursor
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    triggerMode: "hover"
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(card.implicitHeight)

    Column {
      id: card
      anchors.fill: parent
      spacing: Style.space(12)

      Row {
        width: parent.width
        spacing: Style.space(12)

        Cover {
          id: bigCover
          size: Style.space(96)
          radius: Style.space(8)
          glyphSize: Style.font.displayLarge
        }

        Column {
          anchors.verticalCenter: bigCover.verticalCenter
          width: parent.width - bigCover.width - parent.spacing
          spacing: Style.space(4)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.title || "Nada sonando"
            color: Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.artist
            visible: text !== ""
            color: Commons.Color.popups.text
            opacity: 0.75
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.album
            visible: text !== ""
            color: Commons.Color.popups.text
            opacity: 0.5
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      Column {
        width: parent.width
        spacing: 0
        visible: root.length > 0

        PanelSlider {
          width: parent.width
          bar: root.bar
          value: root.progress
          fillColor: Commons.Color.accent
          knobColor: Commons.Color.accent
          enabled: root.player !== null && root.player.canSeek
          onReleased: function(value) { root.seekTo(value) }
        }

        Item {
          width: parent.width
          height: elapsed.implicitHeight

          Text {
            id: elapsed
            anchors.left: parent.left
            text: root.formatTime(root.position)
            color: Commons.Color.popups.text
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            text: root.formatTime(root.length)
            color: Commons.Color.popups.text
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(8)

        Button {
          iconText: "󰒮"
          tooltipText: "Anterior"
          foreground: Commons.Color.popups.text
          enabled: root.player !== null && root.player.canGoPrevious
          opacity: enabled ? 1 : 0.4
          onClicked: root.previous()
        }

        Button {
          iconText: root.playing ? "󰏤" : "󰐊"
          tooltipText: root.playing ? "Pausa" : "Reproducir"
          foreground: Commons.Color.popups.text
          iconSize: Style.font.iconLarge
          horizontalPadding: Style.spacing.panelGap
          enabled: root.player !== null && root.player.canTogglePlaying
          opacity: enabled ? 1 : 0.4
          onClicked: root.playPause()
        }

        Button {
          iconText: "󰒭"
          tooltipText: "Siguiente"
          foreground: Commons.Color.popups.text
          enabled: root.player !== null && root.player.canGoNext
          opacity: enabled ? 1 : 0.4
          onClicked: root.next()
        }
      }

      PanelSeparator {
        foreground: Commons.Color.popups.text
      }

      Button {
        width: parent.width
        iconText: "󰓇"
        text: "Abrir Spotify"
        foreground: Commons.Color.popups.text
        onClicked: root.openSpotify()
      }
    }
  }

  // Album cover with rounded corners; a Spotify glyph stands in while the
  // art loads or when the track has none.
  component Cover: ClippingRectangle {
    id: cover

    property real size: Style.space(18)
    property real glyphSize: Style.font.body

    width: size
    height: size
    color: Qt.alpha(root.foreground, 0.12)

    Image {
      id: art
      anchors.fill: parent
      source: root.artUrl
      sourceSize.width: cover.size * 2
      sourceSize.height: cover.size * 2
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      opacity: status === Image.Ready ? 1 : 0

      Behavior on opacity { NumberAnimation { duration: 250 } }
    }

    Text {
      anchors.centerIn: parent
      visible: art.status !== Image.Ready
      text: "󰓇"
      color: root.foreground
      opacity: 0.7
      font.family: Style.font.family
      font.pixelSize: cover.glyphSize
    }
  }
}
