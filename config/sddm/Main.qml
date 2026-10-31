import QtQuick 2.0
import SddmComponents 2.0

// Omarchy's SDDM theme plus a user picker: Left/Right (or Up/Down, Tab)
// cycles through the accounts, the chosen name is shown above the entry.
// Based on Omarchy's own theme; installed as the "omarchy-kids" theme by
// modules/15-login.sh, which copies Omarchy's images next to this file.
Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"

  property int userCount: userModel.rowCount()
  property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
  property string currentUser: userCount > 0
    ? userModel.data(userModel.index(userIndex, 0), Qt.UserRole + 1)
    : userModel.lastUser
  property string currentRealName: userCount > 0
    ? userModel.data(userModel.index(userIndex, 0), Qt.UserRole + 2)
    : ""
  property bool loginFailed: false
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  function nextUser(step) {
    if (userCount < 2)
      return
    userIndex = (userIndex + step + userCount) % userCount
    password.text = ""
    loginFailed = false
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.focus = true
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 40

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: (root.userCount > 1 ? "◀  " : "")
            + (root.currentRealName !== "" ? root.currentRealName : root.currentUser)
            + (root.userCount > 1 ? "  ▶" : "")
      color: "#c0caf5"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 28
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: entry.width
        height: entry.height

        Image {
          id: entry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: Math.min(password.text.length, 21)

            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 24
          font.letterSpacing: 5
          passwordCharacter: "•"
          color: "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorDelegate: Item {}
          focus: true

          onTextChanged: root.loginFailed = false

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              sddm.login(root.currentUser, password.text, root.sessionIndex)
              event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
              root.nextUser(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
              root.nextUser(-1)
              event.accepted = true
            }
          }
        }
      }
    }
  }

  Component.onCompleted: password.forceActiveFocus()
}
