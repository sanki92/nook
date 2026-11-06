<p align="center"><img src="docs/media/icon.png" width="128" alt="Nook icon"></p>

<h1 align="center">Nook</h1>

<p align="center">A cosy desktop widget for macOS where your Claude Code sessions live as animated pixel mascots.</p>

<p align="center"><img src="docs/media/nook-extra-large.gif" width="704" alt="Nook showing four Claude Code sessions"></p>

Nook sits on your desktop next to Apple's widgets. Each Claude Code session you have running gets its own tile, and its mascot acts out what that session is doing right now:

| Mascot | State | What the session is doing |
|---|---|---|
| Chef hat | **Cooking** | Running a terminal command |
| Hard hat | **Building** | Writing or editing files |
| Book | **Reading** | Reading files or searching |
| Thought bubble | **Thinking** | Working out what to do next |
| Roadblock | **Needs you** | Waiting for your permission or your answer |
| Clipboard | **Delegating** | Its helper agents are still working |
| Trophy | **Done** | Finished its turn |
| Asleep | **Resting** | Idle for a while |
| Dizzy | **Hit a snag** | The last turn ended with an error |

Helper agents (subagents) show up as tiny mascots next to the session name. When nothing is running, the mascot toasts a marshmallow at a campsite.

<p align="center"><img src="docs/media/nook-medium.gif" width="344" alt="Nook at Medium size"></p>

## Install

You need macOS 14 Sonoma or later and [Claude Code](https://claude.com/claude-code).

### Option 1: One command (recommended)

Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/GITHUB_USER/nook/main/install.sh | bash
```

It builds Nook on your Mac and opens it.

- **No warning:** macOS doesn't show its "unidentified developer" warning, because Nook was built on your own Mac.
- **First run:** it needs Apple's free Command Line Tools. If you don't have them, an installer window opens. Run the command again once it finishes.

### Option 2: Download

1. Download `Nook.zip` from the [latest release](https://github.com/GITHUB_USER/nook/releases/latest).
2. Unzip it, then drag **Nook** into your **Applications** folder.
3. Open Nook. macOS blocks it the first time, because Nook isn't signed with a paid Apple developer account.
4. Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Nook, then confirm.

You only need to do this once.

## Using Nook

- **Move it:** drag it anywhere. It snaps into the same grid as Apple's widgets and shows an outline of where it will land. If you drop an Apple widget on top of Nook, Nook slides out of the way.
- **Resize it:** right-click it and choose **Medium**, **Large** or **Extra Large**.
  - **Medium** shows one session at a time. Swipe or scroll on it to switch, or click the dots.
  - **Large** and **Extra Large** show every session, and the tiles grow when fewer are running.
- **Start it with your Mac:** right-click and choose **Open at Login**.
- **Jump to a session:** click its tile, and Nook brings that session's terminal app to the front.
- **Menu bar:** the mascot also lives in your menu bar and shows your most important session. Click it to see every session, or to quit Nook.
- **Fading:** like Apple's widgets, the tiles fade when another app is in front. A session that needs you stays amber, so you won't miss it.

## Privacy

Nook only reads the session files Claude Code already keeps in `~/.claude` on your Mac. It never changes them, needs no account, API key or hooks, and sends nothing over the network.

## Build from source

```bash
git clone https://github.com/GITHUB_USER/nook.git
cd nook
./build.sh --check
./build.sh --install
open ~/Applications/Nook.app
```

| Command | What it does |
|---|---|
| `./build.sh` | Builds `build/Nook.app` for Apple Silicon and Intel |
| `./build.sh --check` | Runs the logic checks |
| `./build.sh --zip` | Packs the app for a release |

Building needs only Apple's Command Line Tools: no Xcode and no packages.

## Uninstall

Right-click Nook and choose **Remove Widget**. That turns off Open at Login and quits it. Then delete the app:

```bash
rm -rf ~/Applications/Nook.app /Applications/Nook.app
defaults delete app.nook.widget
```

## Disclaimer

Nook is an unofficial fan project. It isn't made by, affiliated with or endorsed by Anthropic. Claude and Claude Code are trademarks of Anthropic. The mascot is a fan tribute to Clawd, Claude Code's pixel character.

## License

[MIT](LICENSE)
