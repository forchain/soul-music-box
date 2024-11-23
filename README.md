# Soul Music Box

## Objective
- A MacOS application that monitors Soul chat messages and automatically plays music on QQ Music based on specific message patterns
- Responds back to Soul chat with the currently playing song information

## Features
- Monitors Soul group chat messages
- Detects music play commands (e.g. "播放 歌名 歌手")
- Automatically launches QQ Music
- Searches and plays the specified song on QQ Music
- Responds in Soul chat with "正在播放 歌手《歌名》"

## Command Pattern
- Format: 播放 [歌名] (歌手)
- Example: 播放 爱我的人和我爱的人 游鸿明

## Technical Requirements
- MacOS Application
- Swift
- Apple Event and Accessibility API for app automation
- Accessibility permissions for chat monitoring

## Setup
1. Enable Accessibility permissions:
   - When you first launch the app, it will check for accessibility permissions
   - If permissions are not granted, you'll see instructions in the app:
     1. Open System Preferences > Security & Privacy > Privacy > Accessibility
     2. Click the lock icon to make changes
     3. Add and check the app in the list
     4. Restart the app after granting permissions

2. Configure UI elements:
   - Copy `SoulMusicBox/Resources/UI_CONFIG.yaml.example` to one of these locations:
     1. `UI_CONFIG.yaml` in project root directory (for development)
     2. `Contents/Resources/UI_CONFIG.yaml` in app bundle (for production)
     3. `UI_CONFIG.yaml` in app bundle (for development build)
   - The app will search for the config file in the above order
   - Modify the UI element paths according to your Soul and QQ Music versions
   - Use Accessibility Inspector to verify UI element paths

3. Required permissions in Info.plist:

## UI Configuration
The `UI_CONFIG.yaml` file defines the UI element paths for both Soul and QQ Music. You may need to adjust these paths if:
- You're using different versions of the apps
- The UI structure has changed
- The element identifiers are different

Use macOS Accessibility Inspector to verify and update the paths:
1. Open Xcode > Open Developer Tool > Accessibility Inspector
2. Use the crosshair tool to inspect UI elements
3. Update the YAML file with correct paths and identifiers

Example configuration structure:

```
cp Resources/ui_config.yaml Resources/UI_CONFIG.yaml.example
```
