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

## Required Permissions
The app requires the following permissions:

1. Info.plist permissions:
