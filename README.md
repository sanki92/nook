<p align="center"><img src="docs/media/icon.png" width="112" alt="Nook"></p>

<h1 align="center">Nook</h1>

<p align="center">
  <b>Your Claude Code sessions, living on your desktop.</b><br>
  A tiny pixel crew that cooks, builds and reads while your agents work,<br>
  and waves you down the moment one needs you.
</p>

<p align="center">
  <a href="https://github.com/sanki92/nook/releases/latest"><img src="https://img.shields.io/github/v/release/sanki92/nook?label=download&color=D97757" alt="Download"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-444" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-444" alt="Apple Silicon and Intel">
  <img src="https://img.shields.io/badge/license-MIT-444" alt="MIT license">
</p>

<p align="center"><img src="docs/media/hero.gif" width="720" alt="Nook showing four Claude Code sessions"></p>

## Get it

```bash
curl -fsSL https://raw.githubusercontent.com/sanki92/nook/main/install.sh | bash
```

That's it. Nook builds on your Mac and pops onto your desktop.

Rather click? Grab **Nook.zip** from [Releases](https://github.com/sanki92/nook/releases/latest) and drag it into Applications. The first time you open it, go to System Settings → Privacy & Security and hit **Open Anyway**.

## Meet the crew

Every session gets its own little mascot, acting out whatever it's doing right now.

<table>
  <tr>
    <td align="center"><img src="docs/media/state-cooking.gif" width="230" alt=""><br><b>Cooking</b><br><sub>running a command</sub></td>
    <td align="center"><img src="docs/media/state-building.gif" width="230" alt=""><br><b>Building</b><br><sub>writing code</sub></td>
    <td align="center"><img src="docs/media/state-reading.gif" width="230" alt=""><br><b>Reading</b><br><sub>digging through files</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/media/state-gate.gif" width="230" alt=""><br><b>Needs you</b><br><sub>waiting on your OK</sub></td>
    <td align="center"><img src="docs/media/state-thinking.gif" width="230" alt=""><br><b>Thinking</b><br><sub>figuring out what's next</sub></td>
    <td align="center"><img src="docs/media/state-delegating.gif" width="230" alt=""><br><b>Delegating</b><br><sub>its helpers are on it</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/media/state-done.gif" width="230" alt=""><br><b>Done</b><br><sub>job finished</sub></td>
    <td align="center"><img src="docs/media/state-sleeping.gif" width="230" alt=""><br><b>Resting</b><br><sub>quiet for a while</sub></td>
    <td align="center"><img src="docs/media/state-error.gif" width="230" alt=""><br><b>Hit a snag</b><br><sub>something went wrong</sub></td>
  </tr>
</table>

## Feels like a real widget

<img align="right" src="docs/media/medium.gif" width="276" alt="Nook at Medium size">

- Snaps into the same grid as Apple's widgets, on any screen
- Right-click for **Medium**, **Large** or **Extra Large**
- Swipe the Medium one to flip between sessions
- Helper agents tag along as tiny mascots
- Click a tile to jump straight to its terminal
- Fades with your other widgets while you work in an app

<br clear="right">

It hangs out in your menu bar too, showing whichever session matters most.

<img src="docs/media/menubar.png" width="410" alt="Nook in the menu bar">

## Private by design

Nook only reads the files Claude Code already keeps on your Mac. No account, no API key, and nothing ever leaves your machine.

<p align="center"><img src="docs/media/campfire.gif" width="368" alt="The crew camping out"><br><sub>Nothing running? The crew camps out.</sub></p>

<details>
<summary><b>Build from source</b></summary>

You only need Apple's Command Line Tools.

```bash
git clone https://github.com/sanki92/nook.git
cd nook
./build.sh --install
open ~/Applications/Nook.app
```

</details>

<details>
<summary><b>Uninstall</b></summary>

Right-click Nook and choose **Remove Widget**, then:

```bash
rm -rf ~/Applications/Nook.app /Applications/Nook.app
defaults delete app.nook.widget
```

</details>

<sub>Nook is an unofficial fan project and isn't affiliated with Anthropic. Claude Code is a trademark of Anthropic. MIT licensed.</sub>
